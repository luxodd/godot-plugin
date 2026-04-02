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

const PORT = parseInt(process.argv[2] || "8765", 10);

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
};

const wss = new WebSocketServer({ port: PORT });

let connectionCount = 0;
let commandCount = 0;

wss.on("listening", () => {
  console.log(`[mock-server] listening on ws://localhost:${PORT}`);
});

wss.on("connection", (ws, req) => {
  connectionCount++;
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const token = url.searchParams.get("token") || "(none)";
  console.log(
    `[mock-server] client connected (#${connectionCount}, token=${token})`
  );

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

    const response = JSON.stringify({
      msgver: "1.0",
      type: handler.responseType,
      ts: new Date().toISOString(),
      status: 200,
      payload: handler.payload,
    });

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
