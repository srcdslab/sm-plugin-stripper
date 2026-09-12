#if defined _stripper_included
#endinput
#endif
#define _stripper_included

/*********************************************************
 * Logs an error message into logs/stripper/maps/<mapname>.log
 *
 * @param format	Formatting rules.
 * @param ...		Variable number of format parameters.
 * @noreturn
 *********************************************************/
native void Stripper_LogError(const char[] format, any ...);

/**
 * Called right after stripper logged an error.
 *
 * @param sBuffer	The error message that was logged.
 * @noreturn
 */
forward void Stripper_OnErrorLogged(const char[] sBuffer);

public SharedPlugin __pl_stripper =
{
	name = "Stripper",
	file = "Stripper.smx",
	#if defined REQUIRE_PLUGIN
	required = 1
	#else
	required = 0
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_stripper_SetNTVOptional()
{
    MarkNativeAsOptional("Stripper_LogError");
}
#endif
