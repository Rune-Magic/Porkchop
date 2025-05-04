using System;
using System.IO;
using System.Collections;
using System.Diagnostics;

using Porkchop;
using Porkchop.Data;

namespace Porkchop.Test;

class Data
{
	[Test]
	static void JsonToken()
	{
		StringStream stream = scope .("""
			{
			\r\n
			"hi\\n\\""
			69
			-52.4e+7
			""", .Reference);
		JsonReader reader = scope .(stream, "test-input", FatalPassInstance(), scope .());
		JsonToken[?] expected = .(
			.LSquirly,
			.String("hi\n\""),
			.Int(69),
			.Number(-52.4e+7),
		);
		for (let exp in expected)
		{
			let value = reader.NextToken().Value;
			Test.Assert(value case exp, scope $"Expected {exp}, got {value}");
		}
	}

	[Test]
	static void JsonElement()
	{
		StringStream stream = scope .("""
			{
				"foo": [1, 2],
				"bar": "hi"
			}
			""", .Reference);
		JsonReader reader = scope .(stream, "test-input", FatalPassInstance(), scope .());
		let element = reader.Parse().Value;
		Test.Assert(element["bar"] case .String("hi"));
		Test.Assert(element["foo"][0] case .Int(1));
		Test.Assert(element["foo"][1] case .Int(2));
	}

	struct Foo
	{
		public int int;
		[Force] StringView forced;
		[Optional] public float optional = 3.2f;
		[No] void* no;

		[Tag("type")]
		public enum Bar
		{
			case A(int a, float b);
			case B(StringView);
		}
		public Bar bar;
	}

	[Test]
	static void JsonDeserialize()
	{
		StringStream stream = scope .("""
			{
				"int": 69,
				"forced": "hi",
				"bar": {
					"type": "B",
					"0": "Steak!"
				}
			}
			""", .Reference);
		JsonReader reader = scope .(stream, "test-input", FatalPassInstance(), scope .());
		Foo expected = .() {
			int = 69,
			bar = .B("Steak!")
		};
		expected.[Friend]forced = "hi";
		let result = reader.Deserialize<Foo>().Value;
		Test.Assert(result == expected);
	}
}
