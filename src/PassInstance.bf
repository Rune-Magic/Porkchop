using System;

namespace Porkchop;

interface IPassInstance
{
	public void Error(StringView msg);
	public void Error(StringView msg, params Span<Object> fmtArgs);
}

struct ConsolePassInstance : IPassInstance
{
	public void Error(StringView msg)
	{
		Console.ForegroundColor = .Red;
		Console.WriteLine(msg);
		Console.ForegroundColor = .White;
	}

	public void Error(StringView msg, params Span<Object> fmtArgs)
	{
		Console.ForegroundColor = .Red;
		Console.WriteLine(msg, scope String()..AppendF(msg, params fmtArgs));
		Console.ForegroundColor = .White;
	}
}

struct FatalPassInstance : IPassInstance
{
	public void Error(StringView msg)
	{
		Internal.FatalError(scope .(msg));
	}

	public void Error(StringView msg, params Span<Object> fmtArgs)
	{
		Internal.FatalError(scope String()..AppendF(msg, params fmtArgs));
	}
}
