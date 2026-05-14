// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract VOIDToken is ERC20, Ownable {
    address public arenaContract;

    constructor() ERC20("VOID", "VOID") Ownable(msg.sender) {}

    function setArenaContract(address _arena) external onlyOwner {
        arenaContract = _arena;
    }

    function mintStarterPack(address _to) external {
        require(msg.sender == arenaContract, "Only arena can mint");
        _mint(_to, 500 * 10 ** decimals());
    }

    function burn(address _from, uint256 _amount) external {
        require(msg.sender == arenaContract, "Only arena can burn");
        _burn(_from, _amount);
    }

    function rewardWinner(address _to, uint256 _amount) external {
        require(msg.sender == arenaContract, "Only arena can reward");
        _mint(_to, _amount);
    }
}
