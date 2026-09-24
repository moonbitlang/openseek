///|
/// Read one local raster image relative to the host's workspace.
pub fn definition(workspace_root~ : String) -> @agent_tool.AgentToolDefinition {
  AgentToolDefinition(
    name="read_image",
    description="Read a local PNG, JPEG, GIF, or WebP image (at most 5 MiB) and return the image itself. Paths are relative to the workspace unless absolute. Format is detected from bytes, including extension-less files. Requires an image-capable model route. PTC calls attach images automatically; do not print base64.",
    schema=JsonSchema({
      "type": "object",
      "properties": { "path": { "type": "string" } },
      "required": ["path"],
      "additionalProperties": false,
    }),
    program_callable=true,
    requires_image_input=true,
    concurrent_safe=true,
    execute=Async(arguments => {
      guard arguments is { "path": String(path), .. } && !path.is_blank() else {
        return @agent_tool.respond(
          "error: read_image requires a non-blank path",
          is_error=true,
        )
      }
      let resolved = @workspace_path.resolve(workspace_root, path)
      let image = @image_file.read(resolved)
      @agent_tool.respond_content(
        Content([
          Text(
            "Image: \{resolved}\n\{image.media_type}, \{image.bytes.length()} bytes",
          ),
          Image(image),
        ]),
        brief="read_image \{@agent_tool.brief_basename(path)}",
        data={
          "path": resolved,
          "media_type": image.media_type,
          "bytes": image.bytes.length(),
        },
      )
    }),
  )
}
