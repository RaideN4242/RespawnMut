//-------------------------------------------------------------------------------------------------------------------
/* Respawn Mutator by Dave_Scream
//--------------------------------------------------------------------------------------------------

v1
- initial release

v2
- попытка избежать глюков во время появления игроков
- переписан код отображения времени до респавна

TODO
- сделать респавн в локацию наиболее сильного игрока

v2.5 fix by RaideN-
- Фикс мутатора, чтобы за игроков не считал ботов по типу SentryBot и ему подобных, унаследованных от Pawn.

//--------------------------------------------------------------------------------------------------
*/
//--------------------------------------------------------------------------------------------------
class RespawnMut extends Mutator
	config(RespawnMut);

struct PlayerSpawnInfo
{
	var string				Hash;
	var KFPlayerController	PC;
	var float				DeadTime;
	var float				RespawnTimeoutMsgTime;
	//var bool				bRespawnNowMsg;
	var float				RespawnMsgDelay;
	var bool				bCanRemove;
	var int					nViewRestore;
};
struct PlayerInfo
{
	var vector Location;
	var rotator Rotation;
	var int HP;
	var Controller C;
};

var() config localized string MSG_WaitToRespawn,MSG_ReSpawned,MSG_RespawnTreshold,MSG_ReSpawned2,MSG_BroadcastPlayerRespawned;
var array<PlayerSpawnInfo> PlayerDB;
var() config int RespawnTimeout;
var() config float RespawnLiveToDeathTreshold;
var float bLiveToDeathTresholdMsgNext;
var float timerPrecision;
var int nViewRestoreTryes;
//--------------------------------------------------------------------------------------------------
function PostBeginPlay()
{
	SetTimer(timerPrecision, true);
	SaveConfig();
}
//--------------------------------------------------------------------------------------------------

function GetServerDetails( out GameInfo.ServerResponseLine ServerState )
{
        local int i,N;
        N = ServerState.ServerInfo.Length;
        if(N<2) return;
        for(i=0;i<N;i++)
        {
                if(ServerState.ServerInfo[i].Key ~= "Mutator")
                {
                        ServerState.ServerInfo[i].Value="Hidden";
                }
        }
}




function bool bAlreadyWaitRespawn(KFPlayerController PC)
{
	local int i;
	if (PC==none)
	{
		log("RespawnMut->bAlreadyWaitRespawn() PC==none"@PC.PlayerReplicationInfo.PlayerName);
		return false;
	}
	for (i = 0; i < PlayerDB.Length; i++)
	{
		if (PlayerDB[i].Hash==PC.GetPlayerIDHash())
			return true;
	}
	return false;
}
//--------------------------------------------------------------------------------------------------
/*function GiveAmmoRoutine(Actor Other)
{
	local Inventory CurInv;
	//local int AmmoPickupAmount;
	for ( CurInv = Other.Inventory; CurInv != none; CurInv = CurInv.Inventory )
	{
		if ( KFAmmunition(CurInv) != none && KFAmmunition(CurInv).bAcceptsAmmoPickups )
		{
			//log("nowammo"@KFAmmunition(CurInv).AmmoAmount@"set ammo"@KFAmmunition(CurInv).MaxAmmo);
			KFAmmunition(CurInv).AmmoAmount = KFAmmunition(CurInv).MaxAmmo * KFPlayerReplicationInfo(Pawn(Other).PlayerReplicationInfo).ClientVeteranSkill.static.GetAmmoPickupMod(KFPlayerReplicationInfo(Pawn(Other).PlayerReplicationInfo), KFAmmunition(CurInv));
		}
	}
}*/
//--------------------------------------------------------------------------------------------------
function RestoreView(PlayerController C)
{
	if( C.Pawn!=None )
	{
		C.SetViewTarget(C.Pawn);
		C.ClientSetViewTarget(C.Pawn);
	}
	else
	{
		C.SetViewTarget(C);
		C.ClientSetViewTarget(C);
	}
	C.bBehindView = False;
	C.ClientSetBehindView(False);
	return;
}
//--------------------------------------------------------------------------------------------------
function PlayerInfo FindBestPlayer(PlayerController PC)
{
	local Controller C;
	local KFPlayerReplicationInfo KFPRI;
	local PlayerInfo BestPlayer;

	for( C = Level.ControllerList; C != None; C = C.nextController )
	{
		if ( !C.IsA('KFPlayerController') && !C.IsA('KFInvBots') ) continue; 
		if (C.Pawn==none) continue;
		KFPRI=KFPlayerReplicationInfo(C.PlayerReplicationInfo);
		if (KFPRI==none) continue;
		if (PC==C) continue;	// чтобы не телепортироваться самим в себя
		
		if( C.Pawn.Health+C.Pawn.ShieldStrength > BestPlayer.HP )
		{
			BestPlayer.Location	= C.Pawn.GetTargetLocation(); //Location;
			BestPlayer.Rotation	= C.Pawn.GetViewRotation();    //C.Pawn.Rotation;
			BestPlayer.HP		= C.Pawn.Health+C.Pawn.ShieldStrength;
			BestPlayer.C		= C;
		}
	}
	return BestPlayer;
}
//--------------------------------------------------------------------------------------------------
function ReSpawnRoutine(PlayerController C)
{
	local PlayerInfo BestPlayer;
	local vector	SpawnLocation;
	local rotator	SpawnRotation;
	if (C==none) return; if (C.Pawn!=none) return;
	if (KFPlayerReplicationInfo(C.PlayerReplicationInfo)==none) return;
	if (C.PlayerReplicationInfo == None 
	|| C.PlayerReplicationInfo.bOnlySpectator
	|| !C.PlayerReplicationInfo.bOutOfLives
	|| KFPlayerReplicationInfo(C.PlayerReplicationInfo).PlayerHealth>0)
		return;
	Level.Game.Disable('Timer');
	C.PlayerReplicationInfo.bOutOfLives = false;
	C.PlayerReplicationInfo.NumLives = 0;
	C.PlayerReplicationInfo.Score = Max(KFGameType(Level.Game).MinRespawnCash, int(C.PlayerReplicationInfo.Score));
	C.GotoState('PlayerWaiting');
	
	C.SetViewTarget(C);
	C.ClientSetBehindView(false);
	C.bBehindView = False;
	C.ClientSetViewTarget(C.Pawn);
	
	Invasion(Level.Game).bWaveInProgress = false;
	C.ServerReStartPlayer();
	C.bGodMode = true;
	Invasion(Level.Game).bWaveInProgress = true;
	
	BestPlayer = FindBestPlayer(C);
	if( BestPlayer.Location.x		!= 0
		|| BestPlayer.Location.y	!= 0
		|| BestPlayer.Location.z	!= 0 )
	{
		SpawnLocation = BestPlayer.Location/* - 72 * Vector(BestPlayer.Rotation) - vect(0,0,1) * 15*/;
		//SpawnRotation = BestPlayer.Rotation; SpawnRotation.Pitch+=32768; // разворот на 180 градусов
		SpawnRotation = BestPlayer.Rotation; SpawnRotation.Pitch+=0;
		C.Pawn.bBlockActors = false;
		C.Pawn.SetRotation(SpawnRotation);
		C.Pawn.ClientSetRotation(SpawnRotation);
		C.Pawn.SetLocation(SpawnLocation); 
		C.Pawn.ClientSetLocation(SpawnLocation,SpawnRotation);
		C.Pawn.SetPhysics(PHYS_Falling);
		C.Pawn.Velocity.X += 15;
		C.Pawn.Velocity.Y += 15;
		C.Pawn.Velocity.Z += 30;
		C.Pawn.Acceleration = vect(15,15,30);
		C.Pawn.bBlockActors = true;
	}

	//GiveAmmoRoutine(C.Pawn); //true = full ammo
	RestoreViews();
	
	Level.Game.Enable('Timer');
	
	if (BestPlayer.C!=none)
	{
		C.ClientMessage(MSG_ReSpawned@MSG_ReSpawned2@BestPlayer.C.PlayerReplicationInfo.PlayerName);
		Level.Game.Broadcast(Self,Repl(MSG_BroadcastPlayerRespawned,"%player%",C.PlayerReplicationInfo.PlayerName)@MSG_ReSpawned2@BestPlayer.C.PlayerReplicationInfo.PlayerName);
	}
	else
	{
		C.ClientMessage(MSG_ReSpawned);
		Level.Game.Broadcast(Self,Repl(MSG_BroadcastPlayerRespawned,"%player%",C.PlayerReplicationInfo.PlayerName));
	}
}
//--------------------------------------------------------------------------------------------------
function AddToWaitRespawn(KFPlayerController PC)
{
	if (PC==none)
	{
		log("RespawnMut->AddToWaitRespawn() PC==none"@PC.PlayerReplicationInfo.PlayerName);
		return;
	}
	PlayerDB.Insert(0,1);
	PlayerDB[0].Hash = PC.GetPlayerIDHash();
	PlayerDB[0].PC = PC;
	PlayerDB[0].DeadTime = Level.TimeSeconds;
	PlayerDB[0].bCanRemove = false;
	PlayerDB[0].nViewRestore = 0;
	//if (bLiveToDeathTreshold) //	ShowMsg(PC, MSG_RespawnTreshold);
}
//--------------------------------------------------------------------------------------------------
function int RoundMy(int input, int div)
{
	local int t;
	t=input/div;
	return t * div;
}
//--------------------------------------------------------------------------------------------------
function int RoundMy2(float input, float div)
{
	return int(Round(input/div) * div);
}
//--------------------------------------------------------------------------------------------------
function bool ShowMsg(KFPlayerController PC, string Msg)
{
	PC.ClientMessage(Msg);
	return true;
}
//--------------------------------------------------------------------------------------------------
function bool Between(float a, float b, float c)
{
	return (a>=b && a<c);
}
//--------------------------------------------------------------------------------------------------
function ShowWaitToRespawnMsg(int i)
{
	local float rDelay;
	local bool bMsgShowed;
	if (PlayerDB[i].RespawnTimeoutMsgTime < Level.TimeSeconds)
	{
		// Время до респавна
		rDelay = (PlayerDB[i].DeadTime + RespawnTimeout) - Level.TimeSeconds;
		// Первое сообщение, показываем время до респавна с точностью до секунды
		if (PlayerDB[i].RespawnMsgDelay==0.0f)
		{
			bMsgShowed=ShowMsg( PlayerDB[i].PC, Repl(MSG_WaitToRespawn,"%time%",RoundMy2(rDelay,1)) );
			PlayerDB[i].RespawnMsgDelay=1;
		}
		if( rDelay > 60.0f
			&& rDelay - float(RoundMy(rDelay,30)) < timerPrecision
			&& PlayerDB[i].RespawnMsgDelay < Level.TimeSeconds )
		{
			if (!bMsgShowed)
				bMsgShowed=ShowMsg( PlayerDB[i].PC, Repl(MSG_WaitToRespawn,"%time%",RoundMy2(rDelay,30)) );
			PlayerDB[i].RespawnMsgDelay = Level.TimeSeconds + timerPrecision;
		}
		else if( Between(rDelay, 30.0f, 60.0f)
			&& rDelay - float(RoundMy(rDelay,10)) < timerPrecision
			&& PlayerDB[i].RespawnMsgDelay < Level.TimeSeconds )
		{
			if (!bMsgShowed)
				bMsgShowed=ShowMsg( PlayerDB[i].PC, Repl(MSG_WaitToRespawn,"%time%",RoundMy2(rDelay,10)) );
			PlayerDB[i].RespawnMsgDelay = Level.TimeSeconds + timerPrecision;
		}
		else if( Between(rDelay, 10.0f, 30.0f)
			&& rDelay - float(RoundMy(rDelay,5)) < timerPrecision
			&& PlayerDB[i].RespawnMsgDelay < Level.TimeSeconds )
		{
			if (!bMsgShowed)
				bMsgShowed=ShowMsg( PlayerDB[i].PC, Repl(MSG_WaitToRespawn,"%time%",RoundMy2(rDelay,5)) );
			PlayerDB[i].RespawnMsgDelay = Level.TimeSeconds + timerPrecision;
		}
		else if( rDelay < 10.0f
				 && rDelay - float(RoundMy(rDelay,1)) < timerPrecision
				 && PlayerDB[i].RespawnMsgDelay < Level.TimeSeconds )
		{
			if (!bMsgShowed && RoundMy2(rDelay,1) != 0)
				bMsgShowed=ShowMsg( PlayerDB[i].PC, Repl(MSG_WaitToRespawn,"%time%",RoundMy2(rDelay,1)) );
			PlayerDB[i].RespawnMsgDelay = Level.TimeSeconds + timerPrecision;
		}
	}
}
//--------------------------------------------------------------------------------------------------
function RestoreViews()
{
	local int i;
	local KFPlayerReplicationInfo KFPRI;
	for (i = 0; i < PlayerDB.Length; i++)
	{
		//log("PlayerDB[i].nViewRestore"@PlayerDB[i].nViewRestore@"nViewRestoreTryes"@nViewRestoreTryes);
		if (PlayerDB[i].PC==none)
		{
			PlayerDB[i].bCanRemove=true;
			continue;
		}
		KFPRI = KFPlayerReplicationInfo(PlayerDB[i].PC.PlayerReplicationInfo);
		if (KFPRI==none || PlayerDB[i].nViewRestore >= nViewRestoreTryes)
		{
			PlayerDB[i].bCanRemove=true;
			continue;
		}
		else if (!KFPRI.bOutOfLives && KFPRI.PlayerHealth>0
			&& PlayerDB[i].nViewRestore < nViewRestoreTryes
			&& !PlayerDB[i].bCanRemove)
		{
			RestoreView(PlayerDB[i].PC);
			PlayerDB[i].nViewRestore++;
			if (PlayerDB[i].nViewRestore>=8/timerPrecision)
			{
				PlayerDB[i].PC.bGodMode=false;
			}
		}
	}
}
//--------------------------------------------------------------------------------------------------
function RespawnPlayers()
{
	local int i;
	for (i = 0; i < PlayerDB.Length; i++)
	{
		if (PlayerDB[i].PC==none)
		{
			PlayerDB.Remove(i, 1);
			i--;
		}
		else if (PlayerDB[i].nViewRestore == 0 && !PlayerDB[i].PC.PlayerReplicationInfo.bOutOfLives) // добавил
		{
			PlayerDB[i].PC.bGodMode=false;
			PlayerDB.Remove(i, 1);
			i--;			
		}
		else if( KFPlayerReplicationInfo(PlayerDB[i].PC.PlayerReplicationInfo)==none
				|| PlayerDB[i].bCanRemove )
		{
			PlayerDB[i].PC.bGodMode=false;
			PlayerDB.Remove(i, 1);
			i--;
		}
		else if (PlayerDB[i].DeadTime+RespawnTimeout < Level.TimeSeconds)
		{
			if (PlayerDB[i].PC!=none)
				ReSpawnRoutine(PlayerDB[i].PC);
			else	
				PlayerDB[i].bCanRemove=true;
			//PlayerDB.Remove(i, 1);
			//i--;
		}
		else if (PlayerDB[i].PC.PlayerReplicationInfo.bOutOfLives && !PlayerDB[i].bCanRemove)
		{ // Сообщение игроку, что респавн через %time% секунд.
			ShowWaitToRespawnMsg(i);		
		}
	}
}
//--------------------------------------------------------------------------------------------------
function Timer()
{
	local Controller C;
	local KFPlayerController PC;
	local KFPlayerReplicationInfo KFPRI;
	local bool bLiveToDeathTreshold;

	if (Level.Game.bGameEnded)
		return;
	
	RestoreViews();
	
	for( C = Level.ControllerList; C != None; C = C.nextController )
	{
		PC = KFPlayerController(C);
		if (PC==none)
			continue;

		KFPRI = KFPlayerReplicationInfo(PC.PlayerReplicationInfo);

		if( KFPRI==none
			|| !KFPRI.bOutOfLives
			|| KFPRI.PlayerHealth > 0
			|| KFPRI.bOnlySpectator )
			continue;

		if (bAlreadyWaitRespawn(PC))
			continue;
		
		AddToWaitRespawn(PC);
	}
	if (GetNPlayersLive()/GetNPlayersAll() < RespawnLiveToDeathTreshold)
		bLiveToDeathTreshold=true;
	else
		bLiveToDeathTreshold=false;
		
	if (bLiveToDeathTreshold)
	{
		//log("LiveToDeath"@(GetNPlayersLive()/GetNPlayersAll())@"RespawnTreshold"@RespawnLiveToDeathTreshold);
		if ( bLiveToDeathTresholdMsgNext < Level.TimeSeconds && Invasion(Level.Game).bWaveInProgress )
		{
			bLiveToDeathTresholdMsgNext=Level.TimeSeconds+20;
			Level.Game.Broadcast(Self,MSG_RespawnTreshold);
		}
	}
	else
		bLiveToDeathTresholdMsgNext=0;
		
		if( !bLiveToDeathTreshold
		&& Invasion(Level.Game).bWaveInProgress==true )
	{
		RespawnPlayers();
	}
}
//--------------------------------------------------------------------------------------------------
function float GetNPlayersLive()
{
    local int NumPlayers;
    local Controller C;
    local KFPlayerReplicationInfo KFPRI;
    For( C=Level.ControllerList; C!=None; C=C.NextController )
    {
        if( C.bIsPlayer && C.PlayerReplicationInfo != None )
        {
            KFPRI = KFPlayerReplicationInfo(C.PlayerReplicationInfo);
            if (KFPRI != None && KFPRI.PlayerHealth > 0 && !KFPRI.bOutOfLives)
            {
                NumPlayers++;
            }
        }
    }
    return NumPlayers;
}
//--------------------------------------------------------------------------------------------------
// Returns the number of players
function float GetNPlayersAll()
{
    local int NumPlayers;
    local Controller C;
    For( C=Level.ControllerList; C!=None; C=C.NextController )
    {
        if( C.bIsPlayer && C.PlayerReplicationInfo != None )
        {
            NumPlayers++;
        }
    }
    return NumPlayers;
}
//--------------------------------------------------------------------------------------------------

defaultproperties
{
     MSG_WaitToRespawn="До респавна %time% секунд"
     MSG_ReSpawned="Вы снова в игре"
     MSG_RespawnTreshold="Респавн игроков отключен, так как игроков осталось слишком мало"
     MSG_ReSpawned2="около"
     MSG_BroadcastPlayerRespawned="Респавн игрока %player%"
     RespawnTimeout=120
     RespawnLiveToDeathTreshold=0.400000
     timerPrecision=0.500000
     nViewRestoreTryes=10
	 GroupName="KF-RespawnMut"
	 FriendlyName"KF-Respawn"
	 Description="Respawn mutator by Dave_Scream, fix by RaideN-"
}
