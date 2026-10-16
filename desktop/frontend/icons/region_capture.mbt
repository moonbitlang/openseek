///|
/// Hand-drawn capture corners and pointer, using the toolbar's 16px icon grid.
pub fn icon_region_capture() -> @html.Html {
  @svg.svg(
    width=16,
    height=16,
    view_box="0 0 16 16",
    attrs=@svg.Attrs::build()
      .fill("none")
      .stroke("currentColor")
      .stroke_width("1.25")
      .stroke_linecap("round")
      .stroke_linejoin("round"),
    [
      @svg.path(d="M5 2H2V5M11 2H14V5M14 11V14H11M5 14H2V11"),
      @svg.path(
        d="M5.25 5.25 7 12 8.75 9.25 11.75 8.25Z",
        fill="currentColor",
        stroke="none",
      ),
    ],
  )
}
