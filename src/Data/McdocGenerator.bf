using System;
using System.IO;
using System.Collections;
using System.Diagnostics;

namespace Porkchop.Data;

class McdocToBeefGenerator : Compiler.Generator
{
	public override String Name => "Mcdoc to Beef";

	public override void InitUI()
	{
		AddEdit("filename", "Filename", "Data");
		AddFilePath("path", "Exported Symbols Filepath", "");
	}

	public override void Generate(String outFileName, String outText, ref Flags generateFlags)
	{
		generateFlags |= .AllowRegenerate;
		outFileName.Append(mParams["filename"]);
		BumpAllocator alloc = scope .();
		JsonReader json = scope .(scope FileStream()..Open(mParams["path"]), mParams["path"], ConsolePassInstance(), alloc, .DisallowNull);

	}
}
