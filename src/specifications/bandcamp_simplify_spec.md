# Simplify bandcamp spec

The bandcamp adapter is too complicated.
It currently splits the input point into purchases and wishlist.
Make them separate entry points in the source spec file.

The bandcamp adapter just fetches ONE of the two.

## Questions

- Entry point names? (e.g., `bandcamp_purchases`, `bandcamp_wishlist`?)
    - already done
- How consumer specifies which? Config field? Separate source entries?
    - just different URL. adapter validates URL
- Adapter code changes needed beyond spec?
    - no, adapter should just be simplified.
- Backward compatibility for existing configs?
    - already is. Existing config = new behavior
- Tests define expected behavior?
    - yes, update tests if suitable