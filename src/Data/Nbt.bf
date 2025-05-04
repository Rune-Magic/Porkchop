using System;
using System.IO;
using System.Collections;
using System.Diagnostics;

namespace Porkchop.Data;

class Nbt
{
	enum Tag : uint8
	{
		TAG_End,
		TAG_Byte,
		TAG_Short,
		TAG_Int,
		TAG_Long,
		TAG_Float,
		TAG_Double,
		TAG_Byte_Array,
		TAG_String,
		TAG_List,
		TAG_Compound,
		TAG_Int_Array,
	}

}