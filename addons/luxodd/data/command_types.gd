class_name LuxoddCommandTypes
extends RefCounted

# Request type strings — must match the server's expected wire format exactly.
# Some are PascalCase, some snake_case — this mirrors the Unity plugin behavior.

const GET_PROFILE := "GetProfileRequest"
const GET_USER_BALANCE := "GetUserBalanceRequest"
const ADD_BALANCE := "AddBalanceRequest"
const CHARGE_BALANCE := "ChargeUserBalanceRequest"
const HEALTH_STATUS_CHECK := "health_status_check"
const LEVEL_BEGIN := "level_begin"
const LEVEL_END := "level_end"
const GET_USER_BEST_SCORE := "GetUserBestScoreRequest"
const GET_USER_RECENT_GAMES := "GetUserRecentGamesRequest"
const LEADERBOARD := "leaderboard_request"
const GET_USER_DATA := "GetUserDataRequest"
const SET_USER_DATA := "SetUserDataRequest"
const GET_GAME_SESSION_INFO := "GetGameSessionInfoRequest"
const SEND_STRATEGIC_BETTING_RESULT := "SendStrategicBettingResultRequest"
const GET_BETTING_SESSION_MISSIONS := "GetBettingSessionMissionsRequest"

# Added in 1.1.0, same wire strings as the Unity plugin 1.3.0-preview.1.
const GET_MERCHANT_PRIZE_INFO := "GetMerchantPrizeInfoRequest"
const LEADERBOARD_AROUND_SCORE := "leaderboard_around_score_request"
const SCORE_UPDATE := "score_update"
const GET_TOURNAMENT_INFO := "GetTournamentInfoRequest"

# Messages the server sends on its own, answering no request. Ignored quietly.
const SERVER_NOTICES := ["connect_ack"]

# Responses routed by request_id instead of the request queue.
const SCORE_UPDATE_RESPONSE := "score_update_response"
const GET_TOURNAMENT_INFO_RESPONSE := "GetTournamentInfoResponse"

# Response type -> Request type mapping for routing server responses
const RESPONSE_TO_REQUEST := {
	"GetProfileResponse": GET_PROFILE,
	"GetUserBalanceResponse": GET_USER_BALANCE,
	"AddBalanceResponse": ADD_BALANCE,
	"ChargeUserBalanceResponse": CHARGE_BALANCE,
	"HealthStatusCheckResponse": HEALTH_STATUS_CHECK,
	"health_status_check_response": HEALTH_STATUS_CHECK,
	"LevelBeginResponse": LEVEL_BEGIN,
	"level_begin_response": LEVEL_BEGIN,
	"LevelEndResponse": LEVEL_END,
	"level_end_response": LEVEL_END,
	"GetUserBestScoreResponse": GET_USER_BEST_SCORE,
	"GetUserRecentGamesResponse": GET_USER_RECENT_GAMES,
	"LeaderboardResponse": LEADERBOARD,
	"leaderboard_response": LEADERBOARD,
	"GetUserDataResponse": GET_USER_DATA,
	"SetUserDataResponse": SET_USER_DATA,
	"GetGameSessionInfoResponse": GET_GAME_SESSION_INFO,
	"SendStrategicBettingResultResponse": SEND_STRATEGIC_BETTING_RESULT,
	"GetBettingSessionMissionsResponse": GET_BETTING_SESSION_MISSIONS,
	"GetMerchantPrizeInfoResponse": GET_MERCHANT_PRIZE_INFO,
	"LeaderboardAroundScoreResponse": LEADERBOARD_AROUND_SCORE,
	"leaderboard_around_score_response": LEADERBOARD_AROUND_SCORE,
	"ScoreUpdateResponse": SCORE_UPDATE,
	"score_update_response": SCORE_UPDATE,
	"GetTournamentInfoResponse": GET_TOURNAMENT_INFO,
}
