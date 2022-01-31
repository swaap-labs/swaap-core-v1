// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General internal License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General internal License for more details.

// You should have received a copy of the GNU General internal License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.0;

import "./contracts/Pool.sol";
import "./MyToken.sol";
import "./CryticInterface.sol";
import "./contracts/test/TWBTCOracle.sol";
import "./contracts/test/TWETHOracle.sol";


contract TPoolJoinExit is CryticInterface, Pool {

    uint MAX_BALANCE = Const.BONE * 10**12;
    TWBTCOracle oracle;

    constructor() {
        MyToken t;
        t = new MyToken(type(uint).max, address(this));
        
        // Create Oracle for the initial token
        oracle = new TWBTCOracle();

        // Bind the token with the provided parameters
        bindMMM(address(t), MAX_BALANCE, Const.MAX_WEIGHT, address(oracle));
    }

    // initial token balances is the max amount for uint256
    uint internal initial_token_balance = type(uint).max;

    // this function allows to create as many tokens as needed
    function create_and_bind(uint balance, uint denorm) public returns (address) {
        // Create a new token with initial_token_balance as total supply.
        // After the token is created, each user defined in CryticInterface
        // (crytic_owner, crytic_user and crytic_attacker) receives 1/3 of 
        // the initial balance
        MyToken bt = new MyToken(initial_token_balance, address(this));
        bt.approve(address(this), initial_token_balance);
        // Create Oracle for the buy token
        TWETHOracle oracleBT = new TWETHOracle();
        // Bind the token with the provided parameters
        bindMMM(address(bt), balance, denorm, address(oracleBT));
        return address(bt);
    }

    uint[] internal maxAmountsIn = [type(uint).max, type(uint).max, type(uint).max, type(uint).max, type(uint).max, type(uint).max];
    uint[] internal minAmountsOut = [0, 0, 0, 0, 0, 0, 0, 0];
    uint[8] internal balances = [0, 0, 0, 0, 0, 0, 0, 0];

    uint internal amount = Const.EXIT_FEE;
    uint internal amount1 = Const.EXIT_FEE;
    uint internal amount2 = Const.EXIT_FEE;

    // sets an amount between EXIT_FEE and EXIT_FEE + 2**64 
    function set_input(uint _amount) public {
        amount = Const.EXIT_FEE + _amount % 2**64;
    }

    // sets two amounts between EXIT_FEE and EXIT_FEE + 2**64
    function set_two_inputs(uint _amount1, uint _amount2) public {
        amount1 = Const.EXIT_FEE + _amount1 % 2**64;
        amount2 = Const.EXIT_FEE + _amount2 % 2**64;
    }

    function echidna_joinPool_exitPool_balance_consistency() public returns (bool) {
     
        // if the pool was not finalize, return true (it is unclear how to finalize it) 
        if (!this.isFinalized())
            return true;

        // check this precondition for joinPool
        if (Num.bdiv(amount, this.totalSupply()) == 0)
            return true;

        // save all the token balances in `balances` before calling joinPool / exitPool
        address[] memory current_tokens = this.getCurrentTokens();
        for (uint i = 0; i < current_tokens.length; i++)
            balances[i] = (IERC20(current_tokens[i]).balanceOf(address(msg.sender)));
 
        // save the amount of share tokens
        uint old_balance = this.balanceOf(crytic_owner);

        // call joinPool, with some some reasonable amount
        joinPool(amount, maxAmountsIn);
        // check that the amount of shares decreased
        if (this.balanceOf(crytic_owner) - amount != old_balance)
            return false; 

        // check the precondition for exitPool
        uint exit_fee = Num.bmul(amount, Const.EXIT_FEE); 
        uint pAiAfterExitFee = Num.bsub(amount, exit_fee);
        if(Num.bdiv(pAiAfterExitFee, this.totalSupply()) == 0)
            return true;

        // call exitPool with some reasonable amount
        exitPool(amount, minAmountsOut);
        uint new_balance = this.balanceOf(crytic_owner);
         
        // check that the amount of shares decreased, taking in consideration that 
        // _factory is crytic_owner, so it will receive the exit_fees 
        if (old_balance != new_balance - exit_fee)
            return false;

        // verify that the final token balance are consistent. It is possible
        // to have rounding issues, but it should not allow to obtain more tokens than
        // the ones a user owned
        for (uint i = 0; i < current_tokens.length; i++) {
            uint current_balance = IERC20(current_tokens[i]).balanceOf(address(msg.sender));
            if (balances[i] < current_balance)
                return false; 
        }
 
        return true;
    }

    function echidna_revert_impossible_joinPool_exitPool() public returns (bool) {

        // the amount to join should be smaller to the amount to exit
        if (amount1 >= amount2)
            revert();

        // burn all the shares transfering them to 0x0
        this.transfer(address(0x0), this.balanceOf(msg.sender));
        // join a pool with a reasonable amount. 
        joinPool(amount1, maxAmountsIn);
        // exit a pool with a larger amount
        exitPool(amount2, minAmountsOut);
        return true;
    }

}
