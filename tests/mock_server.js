#!/usr/bin/env node

/**
 * Mock Luxodd WebSocket server for automated testing.
 *
 * Speaks the same JSON command/response protocol as the real backend.
 * Accepts any token, responds to every command type with realistic payloads.
 *
 * Usage: node mock_server.js [port]
 */

const { WebSocketServer } = require("ws");
const fs = require("fs");

const PORT = parseInt(process.argv[2] || "8765", 10);
// Optional: every received frame and connection is appended to this JSON file, so the Godot
// tests can check frame order (for example, the last score_update before level_end).
// Defaults to tests/.mock_frames.json, which the Godot tests read when the variable is unset.
const FRAMES_FILE = process.env.LUXODD_MOCK_FRAMES || require("path").join(__dirname, ".mock_frames.json");
const record = { connections: [], frames: [] };
function saveRecord() {
  if (FRAMES_FILE) fs.writeFileSync(FRAMES_FILE, JSON.stringify(record));
}
saveRecord();

// Map request type -> { responseType, payload }
const COMMAND_RESPONSES = {
  GetProfileRequest: {
    responseType: "GetProfileResponse",
    payload: {
      username: "test_player",
      email: "test@luxodd.com",
      name: "Test Player",
      profile_picture: "https://example.com/avatar.png",
    },
  },
  GetUserBalanceRequest: {
    responseType: "GetUserBalanceResponse",
    payload: { balance: 1500, currency: "credits" },
  },
  AddBalanceRequest: {
    responseType: "AddBalanceResponse",
    payload: { balance: 2000, currency: "credits" },
  },
  ChargeUserBalanceRequest: {
    responseType: "ChargeUserBalanceResponse",
    payload: { balance: 1000, currency: "credits" },
  },
  health_status_check: {
    responseType: "health_status_check_response",
    payload: {},
  },
  level_begin: {
    responseType: "level_begin_response",
    payload: {},
  },
  level_end: {
    responseType: "level_end_response",
    payload: {},
  },
  GetUserBestScoreRequest: {
    responseType: "GetUserBestScoreResponse",
    payload: { best_score: 9999, level: 5 },
  },
  GetUserRecentGamesRequest: {
    responseType: "GetUserRecentGamesResponse",
    payload: { games: [{ score: 500, date: "2026-04-01" }] },
  },
  leaderboard_request: {
    responseType: "leaderboard_response",
    payload: {
      current_user: { username: "test_player", total_score: 5000, rank: 3 },
      leaderboard: [
        { username: "player1", total_score: 10000, rank: 1 },
        { username: "player2", total_score: 7500, rank: 2 },
        { username: "test_player", total_score: 5000, rank: 3 },
      ],
    },
  },
  GetUserDataRequest: {
    responseType: "GetUserDataResponse",
    payload: { user_data: { custom_key: "custom_value", high_score: 42 } },
  },
  SetUserDataRequest: {
    responseType: "SetUserDataResponse",
    payload: {},
  },
  GetGameSessionInfoRequest: {
    responseType: "GetGameSessionInfoResponse",
    payload: { session_type: "Pay2Play", session_id: "sess_abc123" },
  },
  GetBettingSessionMissionsRequest: {
    responseType: "GetBettingSessionMissionsResponse",
    payload: {
      session_id: "sess_abc123",
      missions: [
        { id: "m1", name: "Score 1000", type: "independent", bet: 100 },
      ],
    },
  },
  SendStrategicBettingResultRequest: {
    responseType: "SendStrategicBettingResultResponse",
    payload: {},
  },
  // Added for plugin 1.1.0. Shapes follow the Unity plugin's payload classes.
  GetMerchantPrizeInfoRequest: {
    responseType: "GetMerchantPrizeInfoResponse",
    isActive: true,
    payload: { prize_name: "Test Prize", goal_score: 1000, points_per_second: 5 },
  },
  leaderboard_around_score_request: {
    responseType: "leaderboard_around_score_response",
    payload: {
      leaderboard: [
        { rank: 4, game_handle: "above", score_total: 1200 },
        { rank: 5, game_handle: "test_player", score_total: 1000 },
      ],
    },
  },
};

// Responses that echo fields of the request.
function dynamicResponse(request) {
  const p = request.payload || {};
  switch (request.type) {
    case "score_update":
      return {
        msgver: "1.0", type: "score_update_response", ts: new Date().toISOString(), status: 200,
        payload: { request_id: p.request_id, result: "applied", applied: true, score: p.score, level: p.level },
      };
    case "GetTournamentInfoRequest":
      return {
        msgver: "1", type: "GetTournamentInfoResponse", request_id: p.request_id,
        ts: new Date().toISOString(), status: 200, is_active: true,
        payload: { tournament_id: "t-test-1", dynamic_hardness: 40, min_score: 250 },
      };
    case "level_end":
      // A score of 7777 wins a prize, to test prize_won forwarding.
      return {
        msgver: "1.0", type: "level_end_response", ts: new Date().toISOString(), status: 200,
        payload: p.score === 7777 ? { prize_tickets: [{ id: "tk-1", prize: "Test Prize" }] } : {},
      };
  }
  return null;
}

const wss = new WebSocketServer({ port: PORT });

let connectionCount = 0;
let commandCount = 0;

wss.on("listening", () => {
  console.log(`[mock-server] listening on ws://localhost:${PORT}`);
});

wss.on("connection", (ws, req) => {
  connectionCount++;
  const connId = connectionCount;
  const url = new URL(req.url, "http://localhost");
  const token = url.searchParams.get("token") || "(none)";
  record.connections.push({ conn: connId, path: url.pathname, token });
  saveRecord();
  // Test tokens only; never point this server at real credentials.
  console.log(`[mock-server] client connected (#${connectionCount}, path=${url.pathname})`);

  ws.on("message", (data) => {
    commandCount++;
    const raw = data.toString();
    let request;
    try {
      request = JSON.parse(raw);
    } catch {
      console.error(`[mock-server] invalid JSON: ${raw}`);
      return;
    }

    const type = request.type;
    console.log(`[mock-server] received command: ${type} (#${commandCount})`);
    record.frames.push({ conn: connId, request });
    saveRecord();

    const dynamic = dynamicResponse(request);
    if (dynamic) {
      ws.send(JSON.stringify(dynamic));
      return;
    }

    const handler = COMMAND_RESPONSES[type];
    if (!handler) {
      console.warn(`[mock-server] unknown command type: ${type}`);
      const errorResponse = JSON.stringify({
        msgver: "1.0",
        type: type + "_response",
        ts: new Date().toISOString(),
        status: 404,
        payload: { error: "unknown command" },
      });
      ws.send(errorResponse);
      return;
    }

    const body = {
      msgver: "1.0",
      type: handler.responseType,
      ts: new Date().toISOString(),
      status: 200,
      payload: handler.payload,
    };
    if (handler.isActive !== undefined) body.is_active = handler.isActive;
    const response = JSON.stringify(body);

    ws.send(response);
  });

  ws.on("close", (code) => {
    console.log(`[mock-server] client disconnected (code=${code})`);
  });
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log(
    `[mock-server] shutting down (${connectionCount} connections, ${commandCount} commands served)`
  );
  wss.close(() => process.exit(0));
});

process.on("SIGINT", () => {
  console.log(
    `[mock-server] shutting down (${connectionCount} connections, ${commandCount} commands served)`
  );
  wss.close(() => process.exit(0));
});
