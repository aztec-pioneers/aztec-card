use aztec::protocol_types::traits::{Deserialize, Packable, Serialize};
use std::meta::derive;

#[derive(Deserialize, Packable, Serialize)]
pub struct Timelock {
    spend_limit_timelock: u32,
    withdraw_timelock: u32
}