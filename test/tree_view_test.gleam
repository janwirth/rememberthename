import gleeunit
import gleeunit/should
import output/tree_view

pub fn main() {
  gleeunit.main()
}

pub fn render_generic_document_test() {
  let doc =
    tree_view.Document([
      tree_view.Section(
        "root",
        [
          tree_view.Node(
            "a",
            [
              tree_view.Node("b", []),
              tree_view.Node("c", [tree_view.Node("d", [])]),
            ],
          ),
          tree_view.Node("e", []),
        ],
      ),
    ])

  let expected =
    "root\n"
    <> "├── a\n"
    <> "│   ├── b\n"
    <> "│   └── c\n"
    <> "│       └── d\n"
    <> "└── e"

  tree_view.render(doc)
  |> should.equal(expected)
}
