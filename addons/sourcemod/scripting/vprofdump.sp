#include "sourcemod"
#include "sdktools"
#include "sdkhooks"
#include "dhooks"

#define SNAME "[vprofdump] "
#define ASSERT(%1) if(%1) SetFailState(SNAME..."Assertion failed: \""...#%1..."\"")
#define SPACEOUT 24

public Plugin myinfo = 
{
    name = "VProf dump",
    author = "GAMMA CASE",
    description = "Allows you to dump vprof output to a file",
    version = "1.0.0",
    url = "http://steamcommunity.com/id/_GAMMACASE_/"
};

stock Address operator+(Address l, int r)
{
	return l + view_as<Address>(r);
}

stock Address operator-(Address l, int r)
{
	return l - view_as<Address>(r);
}

bool gIsInProcess;
File gActiveFile;

public void OnPluginStart()
{
	RegAdminCmd("sm_dumpvprof", SM_Dumpvprof, ADMFLAG_ROOT, "Dumps vprof to a specific file.");
	
	GameData gd = new GameData("vprofdump.games");
	
	ASSERT(!gd);
	
	Address srvaddr = gd.GetAddress("PEHeaderAddr");
	ASSERT(srvaddr == Address_Null);
	
	srvaddr += 0x00C88000 - SPACEOUT;
	
	Address straddr = srvaddr;
	StoreToAddress(straddr, 0x00690074, NumberType_Int32);
	StoreToAddress(straddr + 4, 0x00720065, NumberType_Int32);
	StoreToAddress(straddr + 8, 0x0030, NumberType_Int16);
	
	srvaddr += 12;
	
	Address GetModuleHandleWAddr = gd.GetAddress("GetModuleHandleW"); 
	ASSERT(GetModuleHandleWAddr == Address_Null);
	
	delete gd;
	
	StoreToAddress(srvaddr, 0x68, NumberType_Int16);
	StoreToAddress(srvaddr + 1, view_as<int>(straddr), NumberType_Int32);
	StoreToAddress(srvaddr + 5, 0x15FF, NumberType_Int16);
	StoreToAddress(srvaddr + 7, view_as<int>(GetModuleHandleWAddr), NumberType_Int32);
	StoreToAddress(srvaddr + 11, 0xC3, NumberType_Int8);
	
	StartPrepSDKCall(SDKCall_Static);
	
	ASSERT(!PrepSDKCall_SetAddress(srvaddr));
	ASSERT(!PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain));
	
	Handle GetModuleHandleW = EndPrepSDKCall();
	ASSERT(GetModuleHandleW == INVALID_HANDLE);
	
	Address tier0Addr = SDKCall(GetModuleHandleW);
	ASSERT(tier0Addr == Address_Null);
	
	RestoreBytes(srvaddr - 12);
	
	tier0Addr += 0x8100 + 0x1000;
	SetupDhook(tier0Addr);
}

stock void SetupDhook(Address addr)
{
	Handle dhook = DHookCreateDetour(addr, CallConv_STDCALL, ReturnType_Int, ThisPointer_Ignore);
	
	DHookAddParam(dhook, HookParamType_Int, .custom_register = DHookRegister_ECX);
	DHookAddParam(dhook, HookParamType_Int);
	DHookAddParam(dhook, HookParamType_Int);
	DHookAddParam(dhook, HookParamType_Int);
	DHookAddParam(dhook, HookParamType_CharPtr);
	
	ASSERT(!DHookEnableDetour(dhook, false, Dhook_Callback));
}

public MRESReturn Dhook_Callback(Handle hReturn, Handle hParams)
{
	char buff[4096];
	DHookGetParamString(hParams, 5, buff, sizeof(buff));
	
	if(StrContains(buff, "BEGIN VPROF REPORT", false) != -1)
	{
		gActiveFile.WriteLine(buff);
		gIsInProcess = true;
	}
	else if(StrContains(buff, "END VPROF REPORT", false) != -1)
	{
		gActiveFile.WriteLine(buff);
		gIsInProcess = false;
		delete gActiveFile;
	}
	else if(gIsInProcess)
	{
		gActiveFile.WriteLine(buff);
	}
	
	return MRES_Ignored;
}

stock void RestoreBytes(Address addr)
{
	for(int i = 0; i < SPACEOUT - 1; i++)
		StoreToAddress(addr + i, 0x90, NumberType_Int8);
}

public Action SM_Dumpvprof(int client, int args)
{
	if(args < 1)
	{
		ReplyToCommand(client, SNAME..."Usage: sm_dumpvprof <path>");
		return Plugin_Handled;
	}
	
	char path[PLATFORM_MAX_PATH];
	GetCmdArg(1, path, sizeof(path));
	
	gActiveFile = OpenFile(path, "w", true);
	if(gActiveFile == null)
	{
		ReplyToCommand(client, SNAME..."Can't write to \"%s\"!", path);
		return Plugin_Handled;
	}
	
	ServerCommand("sm prof dump vprof");
	
	return Plugin_Handled;
}