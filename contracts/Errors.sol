// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.12;

/**
* @dev Reverts if `condition` is false, with a revert reason containing `errorCode`. Only codes up to 999 are
* supported.
*/
function _require(bool condition, uint256 errorCode) pure {
    if (!condition) _revert(errorCode);
}


/**
 * @dev Reverts with a revert reason containing `errorCode`. Only codes up to 999 are supported.
 */
function _revert(uint256 errorCode) pure {
    // We're going to dynamically create a revert uint256 based on the error code, with the following format:
    // 'BAL#{errorCode}'
    // where the code is left-padded with zeroes to three digits (so they range from 000 to 999).
    //
    // We don't have revert uint256s embedded in the contract to save bytecode size: it takes much less space to store a
    // number (8 to 16 bits) than the individual uint256 characters.
    //
    // The dynamic uint256 creation algorithm that follows could be implemented in Solidity, but assembly allows for a
    // much denser implementation, again saving bytecode size. Given this function unconditionally reverts, this is a
    // safe place to rely on it without worrying about how its usage might affect e.g. memory contents.
    assembly {
        // First, we need to compute the ASCII representation of the error code. We assume that it is in the 0-999
        // range, so we only need to convert three digits. To convert the digits to ASCII, we add 0x30, the value for
        // the '0' character.

        let units := add(mod(errorCode, 10), 0x30)

        errorCode := div(errorCode, 10)
        let tenths := add(mod(errorCode, 10), 0x30)

        // With the individual characters, we can now construct the full uint256. The SWAAP# part is a known constant
        // (0x535741415023): we simply shift this by 16 (to provide space for the 2 bytes of the error code), and add the
        // characters to it, each shifted by a multiple of 8.
        // The revert reason is then shifted left by 192 bits (256 minus the length of the uint256, 8 characters * 8 bits
        // per character = 64) to locate it in the most significant part of the 256 slot (the beginning of a byte
        // array).

        let revertReason := shl(192, add(0x5357414150230000, add(units, shl(8, tenths))))

        // We can now encode the reason in memory, which can be safely overwritten as we're about to revert. The encoded
        // message will have the following layout:
        // [ revert reason identifier ] [ uint256 location offset ] [ uint256 length ] [ uint256 contents ]

        // The Solidity revert reason identifier is 0x08c739a0, the function selector of the Error(uint256) function. We
        // also write zeroes to the next 29 bytes of memory, but those are about to be overwritten.
        mstore(0x0, 0x08c379a000000000000000000000000000000000000000000000000000000000)
        // Next is the offset to the location of the uint256, which will be placed immediately after (20 bytes away).
        mstore(0x04, 0x0000000000000000000000000000000000000000000000000000000000000020)
        // The uint256 length is fixed: 8 characters.
        mstore(0x24, 8)
        // Finally, the uint256 itself is stored.
        mstore(0x44, revertReason)

        // Even if the uint256 is only 8 bytes long, we need to return a full 32 byte slot containing it. The length of
        // the encoded message is therefore 4 + 32 + 32 + 32 = 100.
        revert(0, 100)
    }
}

library Err {

    uint256 internal constant REENTRY = 0;
    uint256 internal constant NOT_FINALIZED = 1;
    uint256 internal constant NOT_BOUND = 2;
    uint256 internal constant NOT_CONTROLLER = 3;
    uint256 internal constant IS_FINALIZED = 4;
    uint256 internal constant MATH_APPROX = 5;
    uint256 internal constant NOT_FACTORY = 6;
    uint256 internal constant FACTORY_CONTROL_REVOKED = 7;
    uint256 internal constant LIMIT_IN = 8;
    uint256 internal constant LIMIT_OUT = 9;
    uint256 internal constant SWAP_NOT_PUBLIC = 10;
    uint256 internal constant BAD_LIMIT_PRICE = 11;
    uint256 internal constant NOT_ADMIN = 12;
    uint256 internal constant NULL_CONTROLLER = 13;
    uint256 internal constant MIN_FEE = 14;
    uint256 internal constant MAX_FEE = 15;
    uint256 internal constant NON_POSITIVE_PRICE = 16;
    uint256 internal constant NOT_POOL = 17;
    uint256 internal constant MIN_TOKENS = 18;
    // uint256 internal constant ERC20_FALSE = 19;
    uint256 internal constant NOT_PENDING_SWAAPLABS = 20;
    // uint256 internal constant MAX_Z = 21;
    uint256 internal constant MIN_HORIZON = 22;
    uint256 internal constant MAX_HORIZON = 23;
    uint256 internal constant MIN_LB_PERIODS = 24;
    uint256 internal constant MAX_LB_PERIODS = 25;
    uint256 internal constant MIN_LB_SECS = 26;
    // uint256 internal constant MAX_LB_SECS = 27;
    uint256 internal constant IS_BOUND = 28;
    uint256 internal constant MAX_TOKENS = 29;
    uint256 internal constant MIN_WEIGHT = 30;
    uint256 internal constant MAX_WEIGHT = 31;
    uint256 internal constant MIN_BALANCE = 32;
    uint256 internal constant MAX_TOTAL_WEIGHT = 33;
    uint256 internal constant NOT_SWAAPLABS = 34;
    uint256 internal constant NULL_ADDRESS = 35;
    uint256 internal constant PAUSED_FACTORY = 36;
    uint256 internal constant X_OUT_OF_BOUNDS = 37;
    uint256 internal constant Y_OUT_OF_BOUNDS = 38;
    uint256 internal constant BPOW_BASE_TOO_LOW = 39;
    uint256 internal constant BPOW_BASE_TOO_HIGH = 40;
    uint256 internal constant PRODUCT_OUT_OF_BOUNDS = 41;
    uint256 internal constant INVALID_EXPONENT = 42;
    uint256 internal constant OUT_OF_BOUNDS = 43;    
    uint256 internal constant MAX_PRICE_UNPEG_RATIO = 44;
    uint256 internal constant PAUSE_WINDOW_EXCEEDED = 45;
    // uint256 internal constant MAX_PRICE_DELAY_SEC = 46;
    uint256 internal constant NOT_PENDING_CONTROLLER = 47;
    uint256 internal constant EXCEEDED_ORACLE_TIMEOUT = 48;
    uint256 internal constant NEGATIVE_PRICE = 49;
    uint256 internal constant BINDED_TOKENS = 50;
    uint256 internal constant PENDING_NEW_CONTROLLER = 51;
    uint256 internal constant UNEXPECTED_BALANCE = 52;
    uint256 internal constant MIN_LB_STEP_PERIODS = 53;
    uint256 internal constant INPUT_LENGTH_MISMATCH = 54;
    uint256 internal constant MIN_MAX_PRICE_UNPEG_RATIO = 55;
    uint256 internal constant MAX_MAX_PRICE_UNPEG_RATIO = 56;

}
