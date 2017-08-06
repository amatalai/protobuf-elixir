defmodule Protobuf.Protoc.Generator.Message do
  alias Protobuf.Protoc.Generator.Util
  alias Protobuf.TypeUtil
  alias Protobuf.Protoc.Generator.Enum, as: EnumGenerator

  def generate_list(ctx, descs) do
    Enum.map(descs, fn(desc) -> generate(ctx, desc) end)
  end

  def generate(%{namespace: ns, package: pkg} = ctx, desc) do
    name = Util.trans_name(desc.name)
    new_namespace = ns ++ [name]
    msg_options = get_msg_opts(desc.options)
    nested_maps = nested_maps([pkg|(ns ++ [desc.name])], desc.nested_type)
    structs = Enum.map_join(desc.field, ", ", fn(f) -> ":#{f.name}" end)
    fields = Enum.map(desc.field, fn(f) -> generate_message_field(ctx, f, nested_maps) end)
    msg_name = new_namespace |> Util.join_name |> Util.attach_pkg(pkg)
    [Protobuf.Protoc.Template.message(msg_name, msg_options, structs, fields)] ++
      Enum.map(desc.nested_type, fn(nested_msg_desc) -> generate(Map.put(ctx, :namespace, new_namespace), nested_msg_desc) end) ++
      Enum.map(desc.enum_type, fn(enum_desc) -> EnumGenerator.generate(Map.put(ctx, :namespace, new_namespace), enum_desc) end)
  end

  def get_msg_opts(opts) do
    msg_options = opts
    opts = %{map: msg_options.map_entry, deprecated: msg_options.deprecated}
    str = Util.options_to_str(opts)
    if String.length(str) > 0, do: ", " <> str, else: ""
  end

  defp nested_maps(ns, nested_types) do
    prefix = "." <> Util.join_name(ns)
    Enum.reduce(nested_types, %{}, fn(desc, acc) ->
      if (desc.options).map_entry do
        Map.put(acc, Util.join_name([prefix, desc.name]), true)
      else
        acc
      end
    end)
  end

  def generate_message_field(ctx, f, nested_maps) do
    opts = field_options(f)
    opts = Map.put(opts, :map, nested_maps[f.type_name])
    opts_str = Util.options_to_str(opts)
    type = TypeUtil.number_to_atom(f.type)
    type = if type == :enum || type == :message do
      Util.trans_type_name(f.type_name, ctx)
    else
      ":#{type}"
    end
    if String.length(opts_str) > 0 do
      ":#{f.name}, #{f.number}, #{label_name(f.label)}: true, type: #{type}, #{opts_str}"
    else
      ":#{f.name}, #{f.number}, #{label_name(f.label)}: true, type: #{type}"
    end
  end

  defp field_options(f) do
    opts = %{enum: f.type == 14, default: default_value(f.type, f.default_value)}
    if f.options, do: merge_field_options(opts, f), else: opts
  end

  defp label_name(1), do: "optional"
  defp label_name(2), do: "required"
  defp label_name(3), do: "repeated"

  defp default_value(_, ""), do: nil
  defp default_value(type, value) do
    val = cond do
      type <= 2 ->
        case Float.parse(value) do
          {v, _} -> v
          :error -> value
        end
      type <= 7 || type == 13 || (type >= 15 && type <= 18) ->
        case Integer.parse(value) do
          {v, _} -> v
          :error -> value
        end
      type == 8 -> String.to_atom(value)
      type == 9 || type == 12 -> value
      type == 14 -> String.to_atom(value)
      true -> nil
    end
    if val == nil, do: val, else: inspect(val)
  end

  defp merge_field_options(opts, f) do
    opts
      |> Map.put(:packed, f.options.packed)
      |> Map.put(:deprecated, f.options.deprecated)
  end
end
