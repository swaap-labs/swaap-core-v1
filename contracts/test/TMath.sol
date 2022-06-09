// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.

// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.

pragma solidity =0.8.12;

import "../Num.sol";

// Contract to wrap internal functions for testing

contract TMath {

    function calcToi(uint a) external pure returns (uint) {
        return Num.toi(a);
    }

    function calcFloor(uint a) external pure returns (uint) {
        return Num.floor(a);
    }

    function calcSubSign(uint a, uint b) external pure returns (uint, bool) {
        return Num.subSign(a, b);
    }

    function calcMul(uint a, uint b) external pure returns (uint) {
        return Num.mul(a, b);
    }

    function calcDiv(uint a, uint b) external pure returns (uint) {
        return Num.div(a, b);
    }

    function calcPowi(uint a, uint n) external pure returns (uint) {
        return Num.powi(a, n);
    }

    function calcPow(uint base, uint exp) external pure returns (uint) {
        return Num.pow(base, exp);
    }

    function calcPowApprox(uint base, uint exp, uint precision) external pure returns (uint) {
        return Num.powApprox(base, exp, precision);
    }
}
