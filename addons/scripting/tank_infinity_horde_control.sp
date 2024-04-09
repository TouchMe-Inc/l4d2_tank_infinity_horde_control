#pragma semicolon              1
#pragma newdecls               required

#include <sourcemod>
#include <left4dhooks>
#include <colors>


public Plugin myinfo = {
	name = "TankInfinityHordeControl",
	author = "Derpduck, TouchMe",
	description = "Monitors and changes state of infinite hordes during tanks",
	version = "build0000",
	url = "https://github.com/TouchMe-Inc/l4d2_tank_infinity_horde_control"
};


#define TRANSLATIONS            "tank_infinity_horde_control.phrases"

/**
 * Teams.
 */
#define TEAM_INFECTED           3

/**
 * Zombie classes.
 */
#define SI_CLASS_TANK           8

/**
 * Sugar.
 */
#define IsTankInPlay            L4D2_IsTankInPlay
#define GetMobSpawnTimer        L4D2Direct_GetMobSpawnTimer
#define GetFurthestSurvivorFlow L4D2_GetFurthestSurvivorFlow
#define GetMapMaxFlowDistance   L4D2Direct_GetMapMaxFlowDistance


enum HordeState
{
	HordeState_None,
	HordeState_Blocked,
	HordeState_Limited,
	HordeState_Unlimited
}


ConVar
	g_cvTankInfinityHordeMin = null,
	g_cvTankInfinityHordeMax = null
;

float
	g_fLastFurthestSurvivorFlow = 0.0,
	g_fCurrentTankInfinityHordeMin = 0.0,
	g_fCurrentTankInfinityHordeMax = 0.0
;

HordeState g_iHordeState = HordeState_None;


public void OnPluginStart()
{
	LoadTranslations(TRANSLATIONS);

	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	g_cvTankInfinityHordeMin = CreateConVar("sm_tank_infinity_horde_min", "1500.0", "", _, true, 0.0);
	g_cvTankInfinityHordeMax = CreateConVar("sm_tank_infinity_horde_max", "1500.0", "", _, true, 0.0);
}

/**
 * Round start event.
 */
void Event_RoundStart(Event event, const char[] sName, bool bDontBroadcast) {
	g_iHordeState = HordeState_None;
}

public void L4D_OnSpawnTank_Post(int iClient, const float vOrigin[3], const float vAngle[3])
{
	if (HasTankInPlay(iClient) || !IsInfiniteHorde()) {
		return;
	}

	g_fLastFurthestSurvivorFlow = GetFurthestSurvivorFlow();
	g_fCurrentTankInfinityHordeMin = g_fLastFurthestSurvivorFlow + GetConVarFloat(g_cvTankInfinityHordeMin);
	g_fCurrentTankInfinityHordeMax = g_fCurrentTankInfinityHordeMin + GetConVarFloat(g_cvTankInfinityHordeMax);

	if (g_fCurrentTankInfinityHordeMax > GetMapMaxFlowDistance()) {
		g_fCurrentTankInfinityHordeMax = GetMapMaxFlowDistance();
	}

	g_iHordeState = HordeState_Blocked;

	CPrintToChatAll("%t%t", "TAG", "HORDE_BLOCK_START");

	CreateTimer(1.0, Timer_CheckHordeState, .flags = TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

Action Timer_CheckHordeState(Handle hTimer)
{
	if (!IsTankInPlay()) {
		return Plugin_Stop;
	}

	if (g_fLastFurthestSurvivorFlow >= GetFurthestSurvivorFlow()) {
		return Plugin_Continue;
	}

	g_fLastFurthestSurvivorFlow = GetFurthestSurvivorFlow();

	float fCurrentPercent = (GetFurthestSurvivorFlow() / GetMapMaxFlowDistance()); // 0.56

	switch(g_iHordeState)
	{
		case HordeState_Blocked:
		{
			float fBufferPercent = (g_fCurrentTankInfinityHordeMin / GetMapMaxFlowDistance()); // 0.55

			float fPercent = (fBufferPercent - fCurrentPercent);

			if (fPercent <= 0.0)
			{
				CPrintToChatAll("%t%t", "TAG", "HORDE_LIMITED_START");
				g_iHordeState = HordeState_Limited;
			}

			else if (fPercent > 0.0 && fPercent <= 1.0)
			{
				CPrintToChatAll("%t%t", "TAG", "HORDE_BLOCK_END", fPercent * 100.0);
			}
		}

		case HordeState_Limited:
		{
			float fBufferPercent = (g_fCurrentTankInfinityHordeMax / GetMapMaxFlowDistance()); // 0.65

			float fPercent = (fBufferPercent - fCurrentPercent);

			if (fPercent <= 0.0)
			{
				g_iHordeState = HordeState_Unlimited;
				CPrintToChatAll("%t%t", "TAG", "HORDE_UNLIMITED");
			}

			else if (fPercent > 0.0)
			{
				CPrintToChatAll("%t%t", "TAG", "HORDE_LIMITED_END", fPercent * 100.0, GetHordePower()* 100.0);
			}
		}
	}

	return Plugin_Continue;
}

/**
 * @brief Called whenever ZombieManager::SpawnMob(int) is invoked
 * @remarks called on natural hordes & z_spawn mob, increases Zombie Spawn
 *			Queue, triggers player OnMobSpawned (vocalizations), sets horde
 *			direction, and plays horde music
 *
 * @param amount		Amount of Zombies to add to Queue
 *
 * @return				Plugin_Handled to block, Plugin_Changed to use overwritten values from plugin, Plugin_Continue otherwise
 */
public Action L4D_OnSpawnMob(int &amount)
{
	if (!IsTankInPlay() || !IsInfiniteHorde()) {
		return Plugin_Continue;
	}

	switch(g_iHordeState)
	{
		case HordeState_None: {
			return Plugin_Continue;
		}

		case HordeState_Blocked: {
			return Plugin_Handled;
		}

		case HordeState_Limited:
		{
			amount = RoundToNearest(amount * GetHordePower());

			return Plugin_Changed;
		}

		case HordeState_Unlimited: {
			return Plugin_Continue;
		}
	}

	return Plugin_Continue;
}

float GetHordePower()
{
	float fHordePower = (g_fLastFurthestSurvivorFlow - g_fCurrentTankInfinityHordeMin) / (g_fCurrentTankInfinityHordeMax - g_fCurrentTankInfinityHordeMin);

	return clamp(0.0, 1.0, fHordePower);
}

bool IsInfiniteHorde() {
	return CTimer_HasStarted(GetMobSpawnTimer()) && CTimer_GetRemainingTime(GetMobSpawnTimer()) <= 10;
}

/**
 * Infected team player?
 */
bool IsClientInfected(int iClient) {
	return (GetClientTeam(iClient) == TEAM_INFECTED);
}

/**
 * Get the zombie player class.
 */
int GetClientClass(int iClient) {
	return GetEntProp(iClient, Prop_Send, "m_zombieClass");
}

bool IsClientTank(int iClient) {
	return (GetClientClass(iClient) == SI_CLASS_TANK);
}

bool HasTankInPlay(int iIgnoreClient = -1)
{
	for (int iClient = 1; iClient <= MaxClients; iClient ++)
	{
		if (!IsClientInGame(iClient)
		|| !IsClientInfected(iClient)
		|| !IsClientTank(iClient)
		|| iClient == iIgnoreClient) {
			continue;
		}

		return true;
	}

	return false;
}

any clamp(any min, any max, any value)
{
	if (value < min) {
		return min;
	} else if (value > max){
		return max;
	}

	return value;
}
