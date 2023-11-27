#if defined _stripper_included
#endinput
#endif
#define _stripper_included

/*********************************************************
 * Log a message into logs/stripper/maps/<mapname>.log
 *
 * @param format	Message to log
 * @noreturn
 *********************************************************/
native void Stripper_LogError(const char[] format, any ...);

/**
 * Called right after stripper loged a error.
 *
 * @param sBuffer      Buffer to store the log message in.
 * @param maxlen         Size of the log buffer.
 * @noreturn
 */
forward void Stripper_OnErrorLogged(char[] sBuffer, int maxlen);

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
    MarkNativeAsOptional("Stripper_Log");
}
#endif
