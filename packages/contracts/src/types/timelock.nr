use aztec::protocol_types::traits::{Deserialize, Packable, Serialize};
use std::meta::derive;

/**
 * Public struct used to track timelocks used to force through spend limit
 * and withdrawals in contentious situations.
 *
 * If a timelock value is 0, it is inactive.
 */
#[derive(Deserialize, Packable, Serialize)]
pub struct Timelock {
    // the block number where a spend limit change was proposed
    spend_limit_timelock: u32,
    // the block number where a withdrawal was proposed
    withdraw_timelock: u32
}