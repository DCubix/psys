"""
Python script to visualize Odin slices, maps, strings, etc. in LLDB.

Based on harold-b's script: https://gist.github.com/harold-b/ef16a5c3ebcceccfc2bc7a5c5dd0058d
and laytan's script: https://gist.github.com/laytan/a94c323a84cef7bcfbdf6d21987fd5a9

Repository: https://github.com/thetarnav/odin-lldb
"""

import lldb
import math
import enum
from collections.abc import Callable


def __lldb_init_module(debugger: lldb.SBDebugger, unused) -> None:
    debugger.HandleCommand("type summary add --python-function odin.struct_summary             --recognizer-function odin.is_type_struct")
    debugger.HandleCommand("type summary add --python-function odin.pointer_summary --no-value --recognizer-function odin.is_type_pointer")
    debugger.HandleCommand("type summary add --python-function odin.union_summary              --recognizer-function odin.is_type_union")
    debugger.HandleCommand("type synth   add --python-class    odin.Union_Children_Provider    --recognizer-function odin.is_type_union")
    debugger.HandleCommand("type summary add --python-function odin.string_summary             --recognizer-function odin.is_type_string")
    debugger.HandleCommand("type synth   add --python-class    odin.Slice_Children_Provider    --recognizer-function odin.is_type_slice")
    debugger.HandleCommand("type summary add --python-function odin.slice_summary              --recognizer-function odin.is_type_slice")
    debugger.HandleCommand("type summary add --python-function odin.array_summary              --recognizer-function odin.is_type_array")
    debugger.HandleCommand("type synth   add --python-class    odin.Map_Children_Provider      --recognizer-function odin.is_type_map")
    debugger.HandleCommand("type summary add --python-function odin.map_summary                --recognizer-function odin.is_type_map")
    debugger.HandleCommand("type summary add --python-function odin.enum_summary    --no-value --recognizer-function odin.is_type_enum")
    debugger.HandleCommand("type summary add --python-function odin.bitset_summary  --no-value --recognizer-function odin.is_type_bitset")
    # debugger.HandleCommand("type synth   add --python-class    odin.Soa_Dynamic_Array_Children_Provider --recognizer-function odin.is_type_soa_dynamic_array")
    debugger.HandleCommand("type summary add --python-function odin.soa_slice_summary           --recognizer-function odin.is_type_soa_dynamic_array")


class Odin_Type(enum.Enum):
    Slice     = "slice"
    Array     = "array"
    String    = "string"
    Map       = "map"
    Struct    = "struct"
    Ptr       = "pointer"
    Enum      = "enum"
    Bitset    = "bitset"
    SOA_Slice = "soa_dynamic_array"
    Other     = "other"
    Union     = "union"

def get_odin_type(t: lldb.SBType) -> Odin_Type:

    if t.type == lldb.eTypeClassStruct:
        if t.name == "string":
            return Odin_Type.String

        if (
            (t.name.startswith("[]") or t.name.startswith("[dynamic]")) and
            not t.name.endswith(']')
        ):
            return Odin_Type.Slice

        if (
            (t.name.startswith("#soa[]") or t.name.startswith("#soa[dynamic]")) and
            not t.name.endswith(']')
        ):
            return Odin_Type.SOA_Slice

        if t.name.startswith("map["):
            return Odin_Type.Map

        return Odin_Type.Struct

    if t.type == lldb.eTypeClassArray:
        return Odin_Type.Array

    if t.type == lldb.eTypeClassEnumeration:
        return Odin_Type.Enum

    if t.type == lldb.eTypeClassUnion:
        if t.name.startswith("bit_set["):
            return Odin_Type.Bitset

        tag = type_get_field_at(t, 0)
        if tag.IsValid() and tag.name == "tag":
            return Odin_Type.Union

        return Odin_Type.Other

    if t.is_pointer:
        return Odin_Type.Ptr

    return Odin_Type.Other

def is_type_slice  (t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.Slice
def is_type_string (t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.String
def is_type_map    (t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.Map
def is_type_struct (t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.Struct
def is_type_pointer(t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.Ptr
def is_type_array  (t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.Array
def is_type_enum   (t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.Enum
def is_type_bitset (t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.Bitset
def is_type_union  (t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.Union
def is_type_soa_dynamic_array(t: lldb.SBType, _dict) -> bool: return get_odin_type(t) == Odin_Type.SOA_Slice

def type_get_field_at(t: lldb.SBType, idx: int) -> lldb.SBTypeMember:
    return t.GetFieldAtIndex(idx)

def value_get_child_at(v: lldb.SBValue, idx: int) -> lldb.SBValue:
    return v.GetChildAtIndex(idx)

def value_get_child(v: lldb.SBValue, name: str) -> lldb.SBValue:
    return v.GetChildMemberWithName(name)

def type_display(t: lldb.SBType) -> str:
    name = t.name.replace("::", ".")
    if t.is_pointer:
        pointee: lldb.SBType = t.GetPointeeType()
        if pointee.IsValid():
            if pointee.name == "void":
                return "rawptr"
            return "^"+type_display(pointee)
        return f"^{name}"
    if t.is_reference: name = f"&{name}"
    return name

def value_summary(value: lldb.SBValue) -> str:
    if not value.IsValid():
        return "<invalid value>"
    return value.GetSummary() or value.GetValue() or "<no value>"

AGGREGATE_SUMMARY_MAX_LEN = 60
SLICE_CHUNK_SIZE          = 1000

def aggregate_value_summary(
    prefix:    str,
    suffix:    str,
    get_value: Callable[[int], str],
    length:    int,
) -> str:
    summary = prefix

    for i in range(length):
        item = get_value(i)

        separator = ", " if i > 0 else ""
        new_length = len(summary) + len(separator) + len(item) + len(suffix)

        if new_length > AGGREGATE_SUMMARY_MAX_LEN and i > 0:
            summary += "..."
            break

        summary += separator + item

    return summary + suffix


# ------------------------------------------------------------------------------
# Struct Values
#
# Default for any struct type that is not a built-in type.

def struct_summary(v: lldb.SBValue, _dict) -> str:
    v = v.GetNonSyntheticValue()

    return aggregate_value_summary("{", "}",
        get_value=lambda i: value_summary(v.GetChildAtIndex(i)),
        length=v.num_children,
    )


# ------------------------------------------------------------------------------
# Enum Values

def enum_summary(v: lldb.SBValue, _dict) -> str:

    num = v.GetValueAsSigned()
    members = v.type.GetEnumMembers()

    if members.IsValid() and 0 <= num < len(members):
        member = members[num]
        if member and member.IsValid() and member.name:
            return f".{member.name}"

    return str(num)


# ------------------------------------------------------------------------------
# Bit Set Values

def bitset_summary(v: lldb.SBValue, _dict) -> str:
    v = v.GetNonSyntheticValue()

    set_flags = []

    for field in v.children:
        if field.IsValid():
            field_value = v.GetChildMemberWithName(field.name)
            if field_value.IsValid() and field_value.GetValueAsUnsigned() != 0:
                set_flags.append(f".{field.name}")

    return "{" + ", ".join(set_flags) + "}"


# ------------------------------------------------------------------------------
# Slice Values
#
# handles both slices and dynamic arrays
# since the layout is the same:
#
#    Raw_Slice :: struct($T: typeid) {
#        data: [^]T,
#        len:  int,
#    }
#
#    Raw_Dynamic_Array :: struct($T: typeid) {
#        data:      [^]T,
#        len:       int,
#        cap:       int,
#        allocator: ^runtime.Allocator,
#    }

def get_len(v: lldb.SBValue) -> int:
    return value_get_child(v.GetNonSyntheticValue(), "len").signed

def get_cap(v: lldb.SBValue) -> int:
    return value_get_child(v.GetNonSyntheticValue(), "cap").signed

def get_data(v: lldb.SBValue) -> lldb.SBValue:
    return value_get_child(v.GetNonSyntheticValue(), "data")

def slice_summary(v: lldb.SBValue, _dict) -> str:

    length = get_len(v)

    # GetChildAtIndex goes through Slice_Children_Provider
    if length > SLICE_CHUNK_SIZE:
        get_value = lambda i: value_summary(v.GetChildAtIndex(i // SLICE_CHUNK_SIZE) \
                                             .GetChildAtIndex(i % SLICE_CHUNK_SIZE))
    else:
        get_value = lambda i: value_summary(v.GetChildAtIndex(i))

    return aggregate_value_summary(f"[{length}]{{", "}", get_value, length)

class Slice_Children_Provider(lldb.SBSyntheticValueProvider):

    def __init__(self, val: lldb.SBValue, _dict) -> None:
        self.val = val

    def update(self) -> None:
        self.len  = get_len(self.val)
        self.data = get_data(self.val)
        assert self.data.type.is_pointer

        self.chunked_len = 0 if not self.len > SLICE_CHUNK_SIZE else math.ceil(self.len / SLICE_CHUNK_SIZE)

    def has_children(self) -> bool:
        return self.len > 0

    def num_children(self) -> int:
        return self.chunked_len if self.chunked_len > 0 else self.len

    def get_child_at_index(self, idx: int) -> lldb.SBValue:
        length = self.num_children()
        assert idx >= 0 and idx < length

        pointee = self.data.deref

        if self.chunked_len > 0:
            array_len   = min(SLICE_CHUNK_SIZE, self.len - idx * SLICE_CHUNK_SIZE)
            range_start = idx * SLICE_CHUNK_SIZE
            name        = f"[{range_start}..<{range_start+array_len}]"
            offset      = idx * pointee.size * SLICE_CHUNK_SIZE
            type        = pointee.type.GetArrayType(array_len)
        else:
            name        = f"[{idx}]"
            offset      = idx * pointee.size
            type        = pointee.type

        return self.data.CreateChildAtOffset(name, offset, type)


# ------------------------------------------------------------------------------
# SOA Slice / Dynamic Array
#
# Layout:
#   struct {
#       field_1:   [^]Field_1,
#       field_2:   [^]Field_2,
#       field_3:   [^]Field_3,
#       ...                     ...or for slices:  ...
#       __$len:    int,                     |      __$len:    int,
#       __$cap:    int,                     |      <no more fields>
#       allocator: ^runtime.Allocator,      |
#   }

def soa_slice_summary(v: lldb.SBValue, _dict) -> str:
    v = v.GetNonSyntheticValue()

    length = value_get_child(v, "__$len").signed
    length_idx = v.GetIndexOfChildWithName("__$len")

    def get_soa_value(i: int) -> str:
        fields: list[lldb.SBValue] = []
        for field_i in range(length_idx): # only user fields
            ptr = value_get_child_at(v, field_i)
            pointee_type = ptr.type.GetPointeeType()
            field = ptr.CreateChildAtOffset(f"[{i}]", i * pointee_type.size, pointee_type)
            fields.append(field)

        return aggregate_value_summary("{", "}", lambda i: value_summary(fields[i]), len(fields))

    return aggregate_value_summary(f"[{length}]{{", "}", get_soa_value, length)


# ------------------------------------------------------------------------------
# Array Values

def array_summary(v: lldb.SBValue, _dict) -> str:
    v = v.GetNonSyntheticValue() if v.IsSynthetic() else v

    length = v.num_children

    return aggregate_value_summary(f"[{length}]{{", "}",
        get_value=lambda i: value_summary(v.GetChildAtIndex(i)),
        length=length,
    )


# ------------------------------------------------------------------------------
# String Values
#
# Same layout as a slice,
#    Raw_String :: struct {
#        data: [^]u8,
#        len:  int,
#    }
#
# Odin strings are UTF-8 encoded

def string_summary(v: lldb.SBValue, _dict) -> str:

    length  = get_len(v)
    if length == 0:
        return '""'

    pointer = get_data(v).GetValueAsUnsigned(0)
    if pointer == 0:
        return struct_summary(v, _dict)

    error = lldb.SBError()
    string_data: bytes = v.process.ReadMemory(pointer, length, error)
    if not error.success:
        print(f"Error reading string data: {error}")
        return "<error reading string>"

    return '"{}"'.format(string_data.decode("utf-8"))


# ------------------------------------------------------------------------------
# Map Values

def map_summary(v: lldb.SBValue, _dict) -> str:

    length = get_len(v)
    if length == 0:
        return "map[0]{}"

    return aggregate_value_summary(
        f"map[{length}]{{", "}",
        get_value=lambda i: f"{value_summary(v.GetChildAtIndex(i*2))} = {value_summary(v.GetChildAtIndex(i*2 + 1))}",
        length=length,
    )

class Map_Children_Provider:

    def __init__(self, val, dict) -> None:
        self.val = val

    def update(self) -> None:
        data = get_data(self.val)

        hash_field = value_get_child(data, "hash")
        key_cell   = value_get_child(data, "key_cell")
        value_cell = value_get_child(data, "value_cell")

        self.key_type = value_get_child(data, "key").type
        self.val_type = value_get_child(data, "value").type

        self.key_ptr = data.unsigned & ~63
        cap_log2     = data.unsigned & 63
        self.cap     = 1 << cap_log2 if cap_log2 > 0 else 0

        assert hash_field.size == 8 # Odin uses 64-bit hashes

        self.key_cell_info = cell_info(self.key_type, key_cell)
        self.val_cell_info = cell_info(self.val_type, value_cell)

        self.val_ptr  = cell_index(self.key_ptr, self.key_cell_info, self.cap)
        self.hash_ptr = cell_index(self.val_ptr, self.val_cell_info, self.cap)

    def num_children(self):
        return get_len(self.val)*2 + 2

    def get_child_at_index(self, index):

        error = lldb.SBError()

        # Second to last one: length
        if index == self.num_children()-2:
            int_type = value_get_child(self.val, "len").type
            len_data = lldb.SBData.CreateDataFromInt(get_len(self.val), int_type.GetByteSize())
            return self.val.CreateValueFromData("len", len_data, int_type)

        # Last one: capacity
        if index == self.num_children()-1:
            int_type = value_get_child(self.val, "len").type
            cap_data = lldb.SBData.CreateDataFromInt(self.cap, int_type.GetByteSize())
            return self.val.CreateValueFromData("cap", cap_data, int_type)

        entry_idx = index // 2
        wants_key = index % 2 == 0

        key_index = 0
        for i in range(self.cap):
            size_of_hash = 8  # Odin uses 64-bit hashes
            tombstone_mask = 1 << (size_of_hash*8 - 1)

            offset_hash = self.hash_ptr + i * size_of_hash

            hash_val = self.val.process.ReadUnsignedFromMemory(offset_hash, size_of_hash, error)
            if not error.success:
                print(error)
                continue
            elif hash_val == 0 or (hash_val & tombstone_mask) != 0:
                continue

            offset_key   = cell_index(self.key_ptr, self.key_cell_info, i)
            offset_value = cell_index(self.val_ptr, self.val_cell_info, i)

            if entry_idx == key_index:
                key_val = self.val.CreateValueFromAddress(f"key{entry_idx}", offset_key, self.key_type)
                if wants_key:
                    return key_val

                return self.val.CreateValueFromAddress(f"[{value_summary(key_val)}]", offset_value, self.val_type)

            key_index += 1

        print("not found")

def cell_info(typev: lldb.SBType, cell_type: lldb.SBValue) -> 'Cell_Info':
    elements_per_cell = 0

    if typev.size != cell_type.size:
        array_type = cell_type.children[0].type
        if array_type.size > 0 and typev.size > 0:
            elements_per_cell = array_type.size / typev.size

    if elements_per_cell == 0:
        elements_per_cell = 1

    return Cell_Info(typev.size, cell_type.size, elements_per_cell)

def cell_index(base: int, info: "Cell_Info", index: int) -> int:
    cell_index = 0
    data_index = 0
    if info.elements_per_cell == 1:
        return base + (index * info.size_of_cell)
    elif info.elements_per_cell == 2:
        cell_index = index >> 1;
        data_index = index & 1;
    elif info.elements_per_cell == 4:
        cell_index = index >> 2;
        data_index = index & 3;
    elif info.elements_per_cell == 8:
        cell_index = index >> 3;
        data_index = index & 7;
    elif info.elements_per_cell == 16:
        cell_index = index >> 4;
        data_index = index & 15;
    elif info.elements_per_cell == 32:
        cell_index = index >> 5;
        data_index = index & 31;
    else:
        cell_index = index // info.elements_per_cell;
        data_index = index % info.elements_per_cell;

    return base + (cell_index * info.size_of_cell) + (data_index * info.size_of_type);

class Cell_Info:
    def __init__(self, size_of_type: int, size_of_cell: int, elements_per_cell: int) -> None:
        self.size_of_type      = size_of_type
        self.size_of_cell      = size_of_cell
        self.elements_per_cell = elements_per_cell


# ------------------------------------------------------------------------------
# Union Values

# Layout:
#    normal & #shared_nil union type:
#        tag: u64
#        v1:  T0
#        v2:  T1
#        ...
#    #no_nil union type:
#        tag: u64
#        v0:  T0
#        v1:  T1
#        ...

def union_is_no_nil(t: lldb.SBType) -> bool:
    first = type_get_field_at(t, 1)
    return first.IsValid() and first.name == "v0"

def union_variant(v: lldb.SBValue) -> lldb.SBValue | None:
    if v.IsSynthetic():
        v = v.GetNonSyntheticValue()

    tag = v.GetChildAtIndex(0)
    assert(tag.name == "tag")

    tag_value = tag.unsigned

    is_no_nil = union_is_no_nil(v.type)

    if not is_no_nil and tag_value == 0:
        return None

    return v.GetChildMemberWithName(f"v{tag_value}")

def union_summary(v: lldb.SBValue, _dict) -> str:
    variant = union_variant(v)
    if variant is None:
        return "nil"

    return f"{type_display(variant.type)}({value_summary(variant)})"

class Union_Children_Provider(lldb.SBSyntheticValueProvider):
    def __init__(self, val: lldb.SBValue, _dict) -> None:
        self.val = val

    def update(self) -> None:
        self.variant = union_variant(self.val)

    def has_children(self) -> bool:
        return self.variant.MightHaveChildren() if self.variant else False

    def num_children(self) -> int:
        return self.variant.num_children if self.variant else 0

    def get_child_at_index(self, idx) -> lldb.SBValue | None:
        return self.variant.GetChildAtIndex(idx) if self.variant else None

    def get_child_index(self, name) -> None | int:
        return self.variant.GetIndexOfChildWithName(name) if self.variant else None



def correct_proc_type_display(t: lldb.SBType) -> str:

    type_name = t.name

    # The type name already contains most of what we need
    # e.g., "proc(f:^main::Foo,b:main::Bar)->(ok:bool)"
    # We need to convert it to: "proc (^main.Foo, main.Bar) -> bool"

    # Extract calling convention if present
    convention = ""
    if '"' in type_name:
        # Handle "contextless" or other conventions
        conv_start = type_name.find('"')
        conv_end = type_name.find('"', conv_start + 1)
        if conv_start != -1 and conv_end != -1:
            convention = type_name[conv_start:conv_end+1]

    # Parse parameters and return types
    # Find the parameter list
    param_start = type_name.find('(')
    param_end = type_name.find(')')
    return_start = type_name.find('->')

    if param_start == -1 or param_end == -1:
        return f"proc {convention} <invalid>"

    params_str = type_name[param_start+1:param_end]

    # Parse parameters - split by comma but handle nested types
    params = []
    if params_str:
        # Simple split for now - this could be improved to handle complex nested types
        param_parts = params_str.split(',')
        for param in param_parts:
            # Extract type after the colon
            if ':' in param:
                param_type = param.split(':', 1)[1].strip()
                # Convert :: to .
                param_type = param_type.replace('::', '.')
                params.append(param_type)

    # Parse return type
    return_type = ""
    if return_start != -1:
        return_part = type_name[return_start+2:]
        if return_part.startswith('(') and return_part.endswith(')'):
            # Multiple return values
            return_inner = return_part[1:-1]
            if return_inner:
                return_parts = return_inner.split(',')
                return_types = []
                for ret in return_parts:
                    if ':' in ret:
                        ret_type = ret.split(':', 1)[1].strip()
                        ret_type = ret_type.replace('::', '.')
                        return_types.append(ret_type)
                if len(return_types) == 1:
                    return_type = return_types[0]
                else:
                    return_type = f"({', '.join(return_types)})"
        else:
            # Single return value
            if ':' in return_part:
                return_type = return_part.split(':', 1)[1].strip()
                return_type = return_type.replace('::', '.')

    # Build the final string
    params_formatted = ', '.join(params)
    if convention:
        result = f"proc {convention} ({params_formatted})"
    else:
        result = f"proc ({params_formatted})"

    if return_type:
        result += f" -> {return_type}"

    return result.replace('  ', ' ').strip()  # Clean up extra spaces

def pointer_summary(ptr: lldb.SBValue, _dict) -> str:

    # nil pointer
    if ptr.GetValueAsUnsigned() == 0:
        return "nil"

    # raw pointer
    if ptr.type.name == "void *":
        return f"rawptr({ptr.GetValue()})"

    # proc pointer
    pointee_type: lldb.SBType = ptr.type.GetPointeeType()
    if pointee_type.type == lldb.eTypeClassFunction:

        params = []
        return_type = None

        return_type_obj = pointee_type.GetFunctionReturnType()
        if return_type_obj.IsValid():
            return_type = type_display(return_type_obj)

        for param_type in pointee_type.GetFunctionArgumentTypes():
            if param_type.IsValid():
                param_type_str = type_display(param_type)
                params.append(param_type_str)

        params_str = ', '.join(params)
        result = f'proc "c" ({params_str})'

        if return_type and return_type != "void":
            result += f" -> {return_type}"

        return result

    # SOA slice pointer
    if ptr.type.name.startswith("#soa"):

        pointer = ptr.GetAddress().GetOffset()

        error = lldb.SBError()
        offset_bytes: bytes = ptr.process.ReadMemory(pointer+8, 8, error)
        if not error.success:
            print(f"Error reading string data: {error}")
            return "<error reading string>"
        else:
            offset_int = int.from_bytes(offset_bytes, 'little')

        v: lldb.SBValue = ptr.Dereference().GetNonSyntheticValue()

        length = value_get_child(v, "__$len").signed

        if offset_int < 0 or offset_int >= length:
            return "<error: out of bounds>"

        length_idx = v.GetIndexOfChildWithName("__$len")

        fields: list[lldb.SBValue] = []
        for field_i in range(length_idx): # only user fields
            ptr = value_get_child_at(v, field_i)
            pointee_type = ptr.type.GetPointeeType()
            field = ptr.CreateChildAtOffset(f"[{offset_int}]", offset_int * pointee_type.size, pointee_type)
            fields.append(field)

        return aggregate_value_summary("#soa&{", "}", lambda i: value_summary(fields[i]), len(fields))

    # Regular pointer
    pointee: lldb.SBValue = ptr.Dereference()
    if not pointee.IsValid():
        return type_display(ptr.type)

    pointee_summary = pointee.GetSummary()
    if pointee_summary:
        return f"&{pointee_summary}"
    else:
        pointee_type_str = type_display(ptr.type)
        pointee_value = pointee.GetValue()
        if pointee_value:
            return f"({pointee_type_str}){pointee_value}"
        else:
            return f"{pointee_type_str}"