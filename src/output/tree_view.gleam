import gleam/list
import gleam/string

pub type Node {
  Node(label: String, children: List(Node))
}

pub type Section {
  Section(title: String, nodes: List(Node))
}

pub type Document {
  Document(sections: List(Section))
}

pub fn render(document: Document) -> String {
  let Document(sections) = document
  sections
  |> render_sections
  |> string.join("\n")
}

fn render_sections(sections: List(Section)) -> List(String) {
  list.fold(sections, #([], True), fn(acc, section) {
    let #(lines, is_first) = acc
    let section_lines = render_section(section)
    case is_first {
      True -> #(section_lines, False)
      False -> #(list.append(lines, ["", ..section_lines]), False)
    }
  })
  |> first
}

fn render_section(section: Section) -> List(String) {
  let Section(title, nodes) = section
  [title, ..render_nodes(nodes, "")]
}

fn render_nodes(nodes: List(Node), prefix: String) -> List(String) {
  list.flatten(
    list.index_map(nodes, fn(node, index) {
      let is_last = index == list.length(nodes) - 1
      render_node(node, prefix, is_last)
    }),
  )
}

fn render_node(node: Node, prefix: String, is_last: Bool) -> List(String) {
  let Node(label, children) = node
  let connector = case is_last {
    True -> "└── "
    False -> "├── "
  }
  let line = prefix <> connector <> label
  case children {
    [] -> [line]
    _ -> {
      let child_prefix =
        prefix
        <> case is_last {
          True -> "    "
          False -> "│   "
        }
      [line, ..render_nodes(children, child_prefix)]
    }
  }
}

fn first(tuple: #(a, b)) -> a {
  let #(first, _) = tuple
  first
}
