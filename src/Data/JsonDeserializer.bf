using System;
using System.Reflection;
using System.Collections;
using System.Diagnostics;

namespace Porkchop.Data;

[AttributeUsage(.Field)]
public struct NoAttribute : Attribute {}

[AttributeUsage(.Field)]
public struct ForceAttribute : Attribute {}

[AttributeUsage(.Field)]
public struct OptionalAttribute : Attribute {}

/// specifies which field should be used as the tag in a tagged union
[AttributeUsage(.Enum)]
public struct TagAttribute : Attribute, this(String key);

interface IJsonSerializeable
{
	//public Result<void> Serialize(JsonBuilder builder);
	public static Result<Self> Deserialize(JsonReader reader);
}

extension JsonReader
{
	public mixin Assert(bool condition, StringView err)
	{
		if (!condition)
		{
			Error(err);
			return .Err;
		}
	}

	public Result<T> Deserialize<T>(bool requireAll = true)
	{
		[Comptime, NoReturn]
		void Emit()
		{
			let type = typeof(T);
			String outString = scope .(256);
			if (type.ImplementsInterface(typeof(IJsonSerializeable)))
			{
				outString.Append("return T.Deserialize(this);");
			}
			else if (type.ImplementsInterface(typeof(ICollection<>)))
			{
				if (type.IsValueType)
					outString.Append("T result = .();\n");
				else
					outString.Append("T result = new:(alloc) .();\n");
				outString.Append("""
					Assert!(Try!(NextToken()) case .LBracket, "Expected array");
					loop: while (true)
					{
						result.Add(Try!(Deserialize<decltype(result.GetEnumerator().GetNext().Value)>()));
						switch (Try!(NextToken()))
						{
						case .Comma:
						case .RBracket: break loop;
						default:
							Error("Expected ',' or ']'");
							return .Err;
						}
					}
					return result;
					""");
			}
			else if (type.IsInteger)
			{
				outString.Append("""
					Assert!(Try!(NextToken()) case .Int(let val), "Expected integer");
					return .Ok((.)val);
					""");
			}
			else if (type.IsFloatingPoint)
			{
				outString.Append("""
					Assert!(Try!(NextToken()) case .Number(let val), "Expected number");
					return .Ok((.)val);
					""");
			}
			else if (type.ImplementsInterface(typeof(IPrintable)))
			{
				outString.Append("""
					Assert!(Try!(NextToken()) case .String(let val), "Expected string");
					return .Ok((.)val);
					""");
			}
			else if (type.IsChar)
			{
				outString.Append("""
					Assert!(Try!(NextToken()) case .String(let val), "Expected string");
					Assert!(val.Length == 1, "Expected single character");
					return .Ok((.)val)[0];
					""");
			}
			else if (type.IsEnum)
			{
				bool noPayload = true;
				for (let entry in type.GetFields())
				{
					if (!entry.IsEnumCase) continue;
					if (!entry.FieldType.IsTuple) continue;
					noPayload = false;
					break;
				}
				if (noPayload)
				{
					outString.Append("""
						Assert!(Try!(NextToken()) case .String(let str), "String expected");
						switch (str)
						{
						""");
					for (let entry in type.GetFields())
					{
						if (!entry.IsEnumCase) continue;
						let name = entry.Name;
						outString.AppendF($"""
							case "{name}": return .Ok(.{name});
							""");
					}
					outString.Append("""
						default:
							Error($"Invalid enum case '{str}'");
							return .Err;
						}
						""");
				}
				else
				{
					TagAttribute tag;
					switch (type.GetCustomAttribute<TagAttribute>())
					{
					case .Ok(out tag):
					case .Err: Runtime.FatalError(scope $"Tagged union type {type} must have [TagSerialize]");
					}
					int tagOffset;
					Type tagType;
					findTag: do
					{
						for (let field in type.GetFields())
						{
							if (field.Name != "$discriminator") continue;
							tagOffset = field.MemberOffset;
							tagType = field.FieldType;
							break findTag;
						}
						Runtime.FatalError();
					}

					outString.AppendF($"""
						Assert!(Try!(NextToken()) case .LSquirly, "Expected object");
						Assert!(Try!(NextToken()) case .String("{tag.key}"), "Expected entry '{tag.key}'");
						Assert!(Try!(NextToken()) case .Colon, "Expected object");
						Assert!(Try!(NextToken()) case .String(let tag), "Expected string");
						T result = default;
						switch (tag)
						{{\n
						""");
					for (let enumcase in type.GetFields())
					{
						if (!enumcase.IsEnumCase) continue;
						outString.AppendF($"""
							case "{enumcase.Name}":
								*({tagType}*)((uint8*)&result + {tagOffset}) = {enumcase.FieldIdx};\n
							""");
						int insertionPoint = outString.Length;
						outString.Append("""
								loop: while (true)
								{
									switch (Try!(NextToken()))
									{
									case .Comma:
									case .RSquirly: break loop;
									default:
										Error("Expected ',' or '}'");
										return .Err;
									}
									Assert!(Try!(NextToken()) case .String(let key), "Expected string");
									switch (key)
									{\n
							""");
						String check = scope .();
						for (let field in enumcase.FieldType.GetFields())
						{
							let name = field.Name;
							String typeStr = scope .()..Append("decltype({bool b = default(T) case .", enumcase.Name, "(");
							for (let field2 in enumcase.FieldType.GetFields())
							{
								if (@field2.Index != 0) typeStr.Append(", ");
								if (field == field2) typeStr.Append("let x");
								else typeStr.Append("?");
							}
							typeStr.Append("); x})");
							outString.AppendF($"""
									case "{name}":
										Assert!(!p_{name}, "Duplicate key");
										Assert!(Try!(NextToken()) case .Colon, "Expected colon");
										*({typeStr}*)((uint8*)&result + {field.MemberOffset}) = Try!(Deserialize<{typeStr}>());
										p_{name} = true;
							""");
							outString.Insert(insertionPoint, scope $"\tbool p_{name} = false;\n");
							check.AppendF($"\t\tAssert!(p_{name}, \"Missing entry '{name}'\");\n");
						}
						outString.Append("""
									}
								}
								if (requireAll)
								{

							""", check, "\t}\n");
					}
					outString.Append("}\n\nreturn result;");
				}

			}
			else if (type.IsStruct || type.IsTuple || type.IsObject)
			{
				outString.Append("var next = Try!(NextToken());\n");
				if (type.IsNullable)
					outString.Append("""
						if (next case .Null) return .Ok(null);
						""");
				outString.Append(
					"""
					Assert!(next case .LSquirly, "Expected object");
					T result = 
					""");
				if (type.IsValueType)
					outString.Append(".();\n");
				else
					outString.Append("new:(alloc) .();\n");
				if (type.FieldCount == 0)
				{
					outString.Append("return result;");
					Compiler.MixinRoot(outString);
					return;
				}
				outString.Append("""
					loop: while (true)
					{
						Assert!(Try!(NextToken()) case .String(let key), "Expected object");
						switch (key)
						{\n
					""");

				String check = scope .(256);
				for (let field in type.GetFields())
				{
					if (!field.HasCustomAttribute<ForceAttribute>())
						if (field.IsConst || field.IsStatic || !field.IsPublic || field.HasCustomAttribute<NoAttribute>())
							continue;
					let name = field.Name;
					let friend = field.IsPublic ? "" : "[Friend]";
					outString.AppendF($"""
						case "{name}":
							Assert!(!{name}, "Duplicate key");
							Assert!(Try!(NextToken()) case .Colon, "Expected colon");
							result.{friend}{name} = Try!(Deserialize<decltype(result.{friend}{name})>());
							{name} = true;\n
					""");
					outString.Insert(0, scope $"bool {name} = false;\n");
					if (!field.HasCustomAttribute<OptionalAttribute>())
						check.AppendF($"\tAssert!({name}, \"Missing field '{name}'\");\n");
				}

				outString.Append("""
						default:
							Error($"Unexpected entry '{key}'");
							return .Err;
						}
						switch (Try!(NextToken()))
						{
						case .Comma:
						case .RSquirly: break loop;
						default:
							Error("Expected ',' or '}'");
							return .Err;
						}
					}

					if (requireAll)
					{
					""", check, """
					}
					return result;
					""");
			}
			else if (type.IsGenericParam) return;
			else Runtime.FatalError(scope $"Unable to generate deserialization code for type {type}");

			Compiler.MixinRoot(outString);
		}

		Emit();
		Runtime.FatalError();
	}
}

namespace System.Collections;

extension Dictionary<TKey, TValue> : Porkchop.Data.IJsonSerializeable where TKey : IPrintable, var
{
	public static System.Result<Self> Deserialize(Porkchop.Data.JsonReader reader)
	{
		reader.Assert!(Try!(reader.NextToken()) case .LSquirly, "Expected object");
		Self result = new:(reader.alloc) .();
		loop: while (true)
		{
			reader.Assert!(Try!(reader.NextToken()) case .String(let key), "Expected string");
			reader.Assert!(Try!(reader.NextToken()) case .Colon, "Expected colon");
			result.Add(key, Try!(reader.Deserialize<TValue>()));
			switch (Try!(reader.NextToken()))
			{
			case .Comma:
			case .RSquirly: break loop;
			default:
				reader.Error("Expected ',' or '}'");
				return .Err;
			}
		}
		return result;
	}
}
