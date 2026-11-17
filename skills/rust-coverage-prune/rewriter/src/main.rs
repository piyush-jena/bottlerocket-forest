//! Insert `#[::rettrace::trace("<file>:<line> <name>")]` before every non-test, non-const
//! function with a body in the given Rust files, on the function's own line so that line
//! numbers do not move. Usage: rewriter <root> <file>...
//! (file paths in labels are relative to <root>).

use quote::ToTokens;
use std::path::Path;
use syn::spanned::Spanned;
use syn::visit::{self, Visit};
use syn::{Attribute, ImplItemFn, ItemFn, ItemImpl, ItemMod, Signature, TraitItemFn, Visibility};

fn is_test_attr(attrs: &[Attribute]) -> bool {
    attrs.iter().any(|a| {
        let text = a.to_token_stream().to_string().replace(' ', "");
        text.contains("cfg(test") || text.contains("cfg(all(test") || text.ends_with("test]")
    })
}

struct Rewriter<'a> {
    file: &'a str,
    inserts: Vec<(usize, usize, String)>,
    impls: Vec<String>,
}

impl Rewriter<'_> {
    fn add(&mut self, attrs: &[Attribute], vis: Option<&Visibility>, sig: &Signature) {
        if is_test_attr(attrs) || sig.constness.is_some() || sig.ident == "main" {
            return;
        }
        let start = match vis {
            Some(v) if !matches!(v, Visibility::Inherited) => v.span().start(),
            _ => sig.span().start(),
        };
        let name = match self.impls.last() {
            Some(ty) => format!("{ty}::{}", sig.ident),
            None => sig.ident.to_string(),
        };
        self.inserts.push((
            start.line,
            start.column,
            format!("{}:{} {}", self.file, start.line, name),
        ));
    }
}

impl<'ast> Visit<'ast> for Rewriter<'_> {
    fn visit_item_mod(&mut self, m: &'ast ItemMod) {
        if !is_test_attr(&m.attrs) {
            visit::visit_item_mod(self, m);
        }
    }

    fn visit_item_fn(&mut self, f: &'ast ItemFn) {
        if is_test_attr(&f.attrs) {
            return;
        }
        self.add(&f.attrs, Some(&f.vis), &f.sig);
        // Nested fns are not named after an enclosing impl.
        let impls = std::mem::take(&mut self.impls);
        visit::visit_item_fn(self, f);
        self.impls = impls;
    }

    fn visit_item_impl(&mut self, i: &'ast ItemImpl) {
        if is_test_attr(&i.attrs) {
            return;
        }
        let ty = i.self_ty.to_token_stream().to_string().replace(' ', "");
        let ty = ty.split('<').next().unwrap_or_default().to_string();
        self.impls.push(ty);
        visit::visit_item_impl(self, i);
        self.impls.pop();
    }

    fn visit_impl_item_fn(&mut self, f: &'ast ImplItemFn) {
        self.add(&f.attrs, Some(&f.vis), &f.sig);
        let impls = std::mem::take(&mut self.impls);
        visit::visit_impl_item_fn(self, f);
        self.impls = impls;
    }

    fn visit_trait_item_fn(&mut self, f: &'ast TraitItemFn) {
        if f.default.is_some() {
            self.add(&f.attrs, None, &f.sig);
        }
        visit::visit_trait_item_fn(self, f);
    }
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let root = Path::new(&args[1]);
    let mut total = 0;
    for file in &args[2..] {
        let path = root.join(file);
        let source = std::fs::read_to_string(&path).expect("read");
        let ast = syn::parse_file(&source).expect("parse");
        let mut r = Rewriter {
            file,
            inserts: Vec::new(),
            impls: Vec::new(),
        };
        r.visit_file(&ast);
        let mut lines: Vec<String> = source.split('\n').map(String::from).collect();
        // Later columns first, so earlier insert positions stay valid.
        r.inserts.sort_by(|a, b| (b.0, b.1).cmp(&(a.0, a.1)));
        for (line, col, label) in &r.inserts {
            let text = &mut lines[line - 1];
            let byte = text.char_indices().nth(*col).map_or(text.len(), |(i, _)| i);
            text.insert_str(byte, &format!("#[::rettrace::trace({label:?})] "));
        }
        total += r.inserts.len();
        eprintln!("{file}: {} functions", r.inserts.len());
        std::fs::write(&path, lines.join("\n")).expect("write");
    }
    eprintln!("total: {total}");
}
