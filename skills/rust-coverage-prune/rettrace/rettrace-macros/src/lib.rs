//! `#[trace("label")]`: count calls, record arguments and the return value.

use proc_macro::TokenStream;
use quote::quote;
use syn::visit::Visit;
use syn::{parse_macro_input, FnArg, ItemFn, LitStr, Pat, ReturnType, Type};

struct ImplTraitFinder(bool);

impl<'ast> Visit<'ast> for ImplTraitFinder {
    fn visit_type_impl_trait(&mut self, _: &'ast syn::TypeImplTrait) {
        self.0 = true;
    }
}

fn traceable_return(ty: &Type) -> bool {
    if matches!(ty, Type::Never(_)) {
        return false;
    }
    let mut finder = ImplTraitFinder(false);
    finder.visit_type(ty);
    !finder.0
}

#[proc_macro_attribute]
pub fn trace(attr: TokenStream, item: TokenStream) -> TokenStream {
    let label = parse_macro_input!(attr as LitStr);
    let f = parse_macro_input!(item as ItemFn);
    let ItemFn {
        attrs,
        vis,
        sig,
        block,
    } = f;
    let arg_records: Vec<_> = sig
        .inputs
        .iter()
        .filter_map(|a| match a {
            FnArg::Typed(pt) => match &*pt.pat {
                Pat::Ident(pi) => Some(pi.ident.clone()),
                _ => None,
            },
            FnArg::Receiver(_) => None,
        })
        .map(|ident| {
            let name = ident.to_string();
            quote! { ::rettrace::arg(#label, #name, (&&::rettrace::Probe(&#ident)).rt_describe()); }
        })
        .collect();
    let records = quote! {
        ::rettrace::call(#label);
        {
            #[allow(unused_imports)]
            use ::rettrace::{ViaDebug as _, ViaOpaque as _};
            #(#arg_records)*
        }
    };
    let inner = if sig.unsafety.is_some() {
        quote! { { unsafe #block } }
    } else {
        quote! { #block }
    };
    let body = match &sig.output {
        ReturnType::Type(_, ty) if traceable_return(ty) => {
            let compute = if sig.asyncness.is_some() {
                quote! { ::rettrace::expect_output::<#ty, _>(async move #inner).await }
            } else {
                quote! { (move || -> #ty #inner)() }
            };
            quote! {{
                #records
                #[allow(clippy::redundant_closure_call)]
                let __rt_ret: #ty = #compute;
                {
                    #[allow(unused_imports)]
                    use ::rettrace::{ViaDebug as _, ViaOpaque as _};
                    ::rettrace::ret(#label, (&&::rettrace::Probe(&__rt_ret)).rt_describe());
                }
                __rt_ret
            }}
        }
        _ => quote! {{
            #records
            #block
        }},
    };
    quote! { #(#attrs)* #vis #sig #body }.into()
}
