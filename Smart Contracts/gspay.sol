// SPDX-License-Identifier: MIT LICENSE



import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./GRewards.sol";



pragma solidity ^0.8.17;

contract Gspay is Ownable, AccessControl {

    GRewards public gs;



  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
 
  constructor(GRewards _gs)  Ownable(msg.sender) {
           gs = _gs;
          _grantRole(DEFAULT_ADMIN_ROLE, msg.sender );
          _grantRole(MANAGER_ROLE, msg.sender);
}



  function safeGsTransfer(address _to, uint256 _amount) external {
    require(hasRole(MANAGER_ROLE, _msgSender()), "Not allowed");
    uint256 gsBal = gs.balanceOf(address(this));
    if (_amount > gsBal){
      gs.transfer(_to, gsBal);
    }
    else {
      gs.transfer(_to, _amount);
    }
  }
}



