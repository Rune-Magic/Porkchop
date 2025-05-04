using System;
using System.IO;
using System.Collections;
using System.Diagnostics;

namespace Porkchop.Data;

class JsonReader : this(Stream source, StringView name, IPassInstance pass, BumpAllocator alloc, Options flags = .None)
{
	public enum Options : uint8
	{
		None = 0,
		DisallowComments = 1,
		DisallowNull = 2,
	}

	(int line, int col) startIdx = default, currentIdx = default;

	public void Error(StringView str)
	{
		pass.Error($"{str} at line {startIdx.line+1}:{startIdx.col+1} in {name}");
	}

	public void Error(StringView str, params Span<Object> args)
	{
		pass.Error(scope $"{str} at line {startIdx.line}:{startIdx.col} in {name}", params args);
	}

	protected Result<char8> PeekNext() => source.Peek<char8>();
	protected void MoveBy(int amount)
 	{
		for (int i < amount)
			if (source.Read<char8>().Value == '\n')
			{
				currentIdx.line++;
				currentIdx.col = 0;
			}
			else currentIdx.col++;
	}

	protected bool Consume(char8 c)
	{
		if (PeekNext() not case .Ok(c)) return false;
		MoveBy(1);
		return true;
	}

	protected bool Consume(StringView str)
	{
		String buf = scope .(str.Length);
		if (source.ReadStrSized32(str.Length, ..buf) == str)
		{
			for (let c in buf.RawChars)
				if (c == '\n')
				{
					currentIdx.line++;
					currentIdx.col = 0;
				}
				else currentIdx.col++;
			return true;
		}
		source.Seek(source.Position - str.Length);
		return false;
	}

	public Result<JsonToken> NextToken()
	{
		while (PeekNext() case .Ok(let val) && val.IsWhiteSpace) MoveBy(1);
		if (source.Position >= source.Length) return .Ok(.EOF);
		startIdx = currentIdx;

		if (Consume('{')) return .Ok(.LSquirly);
		if (Consume('}')) return .Ok(.RSquirly);
		if (Consume('[')) return .Ok(.LBracket);
		if (Consume(']')) return .Ok(.RBracket);
		if (Consume(',')) return .Ok(.Comma);
		if (Consume(':')) return .Ok(.Colon);

		if (Consume('"'))
		{
			String str = scope .(32);
			bool escape = false;
			while (true)
			{
				if (PeekNext() not case .Ok(let c))
				{
					Error("Expected '\"'");
					return .Err;
				}
				MoveBy(1);
				if (c == '"' && !escape) break;
				if (c == '\\') escape = !escape;
				else escape = false;
				str.Append(c);
			}
			String outString = new:alloc .(str.Length);
			switch (str.Unescape(outString))
			{
			case .Ok:
				return .Ok(.String(outString));
			case .Err:
				Error($"Unable to unescape string: \"{str}\"");
				return .Err;
			}
		}

		if (Consume("false")) return .Ok(.False);
		if (Consume("true")) return .Ok(.True);
		if (Consume("null"))
		{
			if (flags.HasFlag(.DisallowNull))
			{
				Error("null is not allowed");
				return .Err;
			}
			return .Ok(.Null);
		}

		if (Consume("//"))
		{
			if (flags.HasFlag(.DisallowComments))
			{
				Error("Comments are not allowed");
				return .Err;
			}
			while (!Consume('\n')) MoveBy(1);
		}

		if (Consume("/*"))
		{
			if (flags.HasFlag(.DisallowComments))
			{
				Error("Comments are not allowed");
				return .Err;
			}
			while (!Consume("*/")) MoveBy(1);
		}

		Debug.Assert(PeekNext() case .Ok(var c));
		MoveBy(1);

		if (c.IsNumber || "+-.".Contains(c))
		{
			String builder = scope .(16)..Append(c);
			while (true)
			{
				if (PeekNext() not case .Ok(out c) || (!c.IsLetterOrDigit && !"+-.".Contains(c)))
					break;
				MoveBy(1);
				builder.Append(c);
			}
			switch (int.Parse(builder))
			{
			case .Ok(let val):
				return .Ok(.Int(val));
			case .Err(let err):
				switch (double.Parse(builder))
				{
				case .Ok(let val):
					return .Ok(.Number(val));
				case .Err:
					Error($"Malformed number: {err}");
					return .Err;
				}
			}
		}

		Error($"Unexpected '{c}'");
		return .Err;
	}

	public Result<JsonElement> Parse()
	{
		switch (Try!(NextToken()))
		{
		case .True: return .Ok(true);
		case .False: return .Ok(false);
		case .Null: return .Ok(null);
		case .Int(let val): return .Ok(val);
		case .Number(let val): return .Ok(val);
		case .String(let val): return .Ok(val);
		case .EOF:
			Error("Expected element");
			return .Err;
		case .LSquirly:
			Dictionary<String, JsonElement> object = new:alloc .(4);
			loop: while (true)
			{
				String key;
				if (!(Try!(NextToken()) case .String(out key)))
				{
					Error("Expected string");
					return .Err;
				}

				if (!(Try!(NextToken()) case .Colon))
				{
					Error("Expected ':'");
					return .Err;
				}

				object.Add(key, Try!(Parse()));

				switch (Try!(NextToken()))
				{
				case .Comma:
				case .RSquirly:
					break loop;
				default:
					Error("Expected ',' or '}'");
					return .Err;
				}
			}
			return .Ok(.Object(object));
		case .LBracket:
			List<JsonElement> array = new:alloc .(4);
			loop: while (true)
			{
				array.Add(Try!(Parse()));
	
				switch (Try!(NextToken()))
				{
				case .Comma:
				case .RBracket:
					break loop;
				default:
					Error("Expected ',' or ']'");
					return .Err;
				}
			}
			return .Ok(.Array(array));
		case .Comma:
			Error("Unexpected ','");
			return .Err;
		case .Colon:
			Error("Unexpected ':'");
			return .Err;
		case .RBracket:
			Error("Unexpected ']'");
			return .Err;
		case .RSquirly:
			Error("Unexpected '}'");
			return .Err;
		}
	}
}