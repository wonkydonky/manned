extern crate web;

use std::io::{stdin,Read};

fn main() {
    let rd = stdin();
    let mut buf = String::new();
    rd.lock().read_to_string(&mut buf).unwrap();
    println!("{}", web::grotty2html(&buf));
}

