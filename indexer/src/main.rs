#[macro_use] extern crate log;
#[macro_use] extern crate lazy_static;
extern crate env_logger;
extern crate regex;
extern crate libarchive3_sys;
extern crate libc;

mod archive;
mod archread;
mod man;

fn main() {
    env_logger::init().unwrap();
    info!("Hello, world!");
}
