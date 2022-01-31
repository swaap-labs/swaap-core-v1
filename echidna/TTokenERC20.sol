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
import "./contracts/PoolToken.sol";


contract CryticInterface{
    address internal crytic_owner = address(0x41414141);
    address internal crytic_user = address(0x42424242);
    address internal crytic_attacker = address(0x43434343);

    uint internal initialTotalSupply = type(uint).max;
    uint internal initialBalance_owner;
    uint internal initialBalance_user;
    uint internal initialBalance_attacker;

    uint initialAllowance_user_attacker;
    uint initialAllowance_attacker_user;
    uint initialAllowance_attacker_attacker;
}

contract TPoolTokenERC20 is CryticInterface, PoolToken {

    constructor() {
        _totalSupply = initialTotalSupply;
        _balance[crytic_owner] = 0;
        _balance[crytic_user] = initialTotalSupply/2;
        initialBalance_user = initialTotalSupply/2;
        _balance[crytic_attacker] = initialTotalSupply/2;
        initialBalance_attacker = initialTotalSupply/2;
    }

    
    /*
    Type: Code quality
    Return: Success
    */
    function echidna_zero_always_empty() public view returns(bool){
        return this.balanceOf(address(0x0)) == 0;
    }

    /*
    Type: Code Quality
    Return: 
    */
    function echidna_approve_overwrites() public returns (bool) {
        bool approve_return; 
        approve_return = approve(crytic_user, 10);
        require(approve_return);
        approve_return = approve(crytic_user, 20);
        require(approve_return);
        return this.allowance(msg.sender, crytic_user) == 20;
    }

    /*
    Type: Undetermined severity
    Return: Success
    */
    function echidna_balance_less_than_totalSupply() public view returns(bool){
        return this.balanceOf(msg.sender) <= _totalSupply;
    }

    /*
    Type: Low severity
    Return: Success
    */
    function echidna_totalSupply_balances_consistency() public view returns(bool){
        return this.balanceOf(crytic_owner) + this.balanceOf(crytic_user) + this.balanceOf(crytic_attacker) <= totalSupply();
    }

    /*
    Properties: Transferable
    */

    /*
    Type: Code Quality
    Return: Fail or Throw
    */
    function echidna_revert_transfer_to_zero() public returns (bool) {
        if (this.balanceOf(msg.sender) == 0)
          revert();
        return transfer(address(0x0), this.balanceOf(msg.sender));
    }

    /*
    Type: Code Quality
    Return: Fail or Throw
    */
    function echidna_revert_transferFrom_to_zero() public returns (bool) {
        uint balance = this.balanceOf(msg.sender);
        bool approve_return = approve(msg.sender, balance);
        return transferFrom(msg.sender, address(0x0), this.balanceOf(msg.sender));
    }

    /*
    Type: ERC20 Standard
    Fire: Transfer(msg.sender, msg.sender, balanceOf(msg.sender))
    Return: Success
    */
    function echidna_self_transferFrom() public returns(bool){
        uint balance = this.balanceOf(msg.sender);
        bool approve_return = approve(msg.sender, balance);
        bool transfer_return = transferFrom(msg.sender, msg.sender, balance);
        return (this.balanceOf(msg.sender) == balance) && approve_return && transfer_return;
    }


    /*
    Type: ERC20 Standard
    Return: Success
    */
    function echidna_self_transferFrom_to_other() public returns(bool){
        uint balance = this.balanceOf(msg.sender);
        bool approve_return = approve(msg.sender, balance);
        bool transfer_return = transferFrom(msg.sender, crytic_owner, balance);
        return (this.balanceOf(msg.sender) == 0) && approve_return && transfer_return;
    }

    /*
    Type: ERC20 Standard
    Fire: Transfer(msg.sender, msg.sender, balanceOf(msg.sender))
    Return: Success
    */
    function echidna_self_transfer() public returns(bool){
        uint balance = this.balanceOf(msg.sender);
        bool transfer_return = transfer(msg.sender, balance);
        return (this.balanceOf(msg.sender) == balance) && transfer_return;
    }

    /*
    Type: ERC20 Standard
    Fire: Transfer(msg.sender, other, 1)
    Return: Success
    */
    function echidna_transfer_to_other() public returns(bool){
        uint balance = this.balanceOf(msg.sender);
        address other = crytic_user;
        if (other == msg.sender) {
           other = crytic_owner;
        }
        if (balance >= 1) {
           bool transfer_other = transfer(other, 1);
           return (this.balanceOf(msg.sender) == balance-1) && (this.balanceOf(other) >= 1) && transfer_other;
        }
        return true;
    }

    /*
    Type: ERC20 Standard
    Fire: Transfer(msg.sender, user, balance+1)
    Return: Fail or Throw
    */
    function echidna_revert_transfer_to_user() public returns(bool){
        uint balance = this.balanceOf(msg.sender);
        if (balance == (2 ** 256 - 1))
            revert();
        bool transfer_other = transfer(crytic_user, balance+1);
        return true;
    }
  

    /*
    Properties: Not Mintable
    */

    /*
    Type: Undetermined severity
    Return: Success
    */
    function echidna_totalSupply_constant() public view returns(bool){
        return initialTotalSupply == totalSupply();
    }

}
