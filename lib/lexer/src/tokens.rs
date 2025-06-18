
// Tokenizer
// 1. Does not allocate anything
// 2. Does not copy anything
// 3. Operate on bytes, not streams of bytes (parralellizable)
pub struct Token {
    struct Loc {
        
    }

    tag: Tag,
    loc: Loc,
}
