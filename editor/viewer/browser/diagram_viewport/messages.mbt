///|
priv enum DiagramMessage {
  D2Controls
  UmlControls
  MermaidControls
  TogglePan
  ZoomOut
  ZoomIn
  FitDiagram
  DragToResize
  ResizeDiagram
  InteractiveDiago
  InteractiveUml
  InteractiveMermaid
}

///|
fn diagram_text(
  language : @localization.Language,
  message : DiagramMessage,
) -> String {
  match language {
    English =>
      match message {
        D2Controls => "D2 diagram controls"
        UmlControls => "UML diagram controls"
        MermaidControls => "Mermaid diagram controls"
        TogglePan => "Toggle pan mode"
        ZoomOut => "Zoom out"
        ZoomIn => "Zoom in"
        FitDiagram => "Fit diagram"
        DragToResize => "Drag to resize"
        ResizeDiagram => "Resize diagram"
        InteractiveDiago => "Interactive Diago diagram"
        InteractiveUml => "Interactive UML diagram"
        InteractiveMermaid => "Interactive Mermaid diagram"
      }
    SimplifiedChinese =>
      match message {
        D2Controls => "D2 图表控件"
        UmlControls => "UML 图表控件"
        MermaidControls => "Mermaid 图表控件"
        TogglePan => "切换平移模式"
        ZoomOut => "缩小"
        ZoomIn => "放大"
        FitDiagram => "使图表适应视口"
        DragToResize => "拖动以调整大小"
        ResizeDiagram => "调整图表大小"
        InteractiveDiago => "可交互的 Diago 图表"
        InteractiveUml => "可交互的 UML 图表"
        InteractiveMermaid => "可交互的 Mermaid 图表"
      }
    TraditionalChinese =>
      match message {
        D2Controls => "D2 圖表控制項"
        UmlControls => "UML 圖表控制項"
        MermaidControls => "Mermaid 圖表控制項"
        TogglePan => "切換平移模式"
        ZoomOut => "縮小"
        ZoomIn => "放大"
        FitDiagram => "讓圖表符合檢視區域"
        DragToResize => "拖曳以調整大小"
        ResizeDiagram => "調整圖表大小"
        InteractiveDiago => "可互動的 Diago 圖表"
        InteractiveUml => "可互動的 UML 圖表"
        InteractiveMermaid => "可互動的 Mermaid 圖表"
      }
    Japanese =>
      match message {
        D2Controls => "D2 図の操作"
        UmlControls => "UML 図の操作"
        MermaidControls => "Mermaid 図の操作"
        TogglePan => "パンモードを切り替え"
        ZoomOut => "縮小"
        ZoomIn => "拡大"
        FitDiagram => "図を表示領域に合わせる"
        DragToResize => "ドラッグしてサイズを変更"
        ResizeDiagram => "図のサイズを変更"
        InteractiveDiago => "操作可能な Diago 図"
        InteractiveUml => "操作可能な UML 図"
        InteractiveMermaid => "操作可能な Mermaid 図"
      }
    Spanish =>
      match message {
        D2Controls => "Controles del diagrama D2"
        UmlControls => "Controles del diagrama UML"
        MermaidControls => "Controles del diagrama Mermaid"
        TogglePan => "Alternar modo de desplazamiento"
        ZoomOut => "Alejar"
        ZoomIn => "Acercar"
        FitDiagram => "Ajustar diagrama"
        DragToResize => "Arrastra para cambiar el tamaño"
        ResizeDiagram => "Cambiar el tamaño del diagrama"
        InteractiveDiago => "Diagrama Diago interactivo"
        InteractiveUml => "Diagrama UML interactivo"
        InteractiveMermaid => "Diagrama Mermaid interactivo"
      }
  }
}
