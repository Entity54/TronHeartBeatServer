// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Will.sol";

contract willFactory {
    address public admin;
    uint256 public willsAddressesLength;
    address[] public willsAddresses;
    mapping(address => uint256) public willLocation; //what is the location of the will in the willsAddresses array
    mapping(address => bool) public willOwners; //checks if an address is a will owner
    mapping(address => address) public accountOwnsWill; //given an account address we see which will it owns

    event newWillCreated(
        address willAdmin,
        address willAddress,
        uint256 blockNum
    );
    event willTerminated(address willAddress, uint256 blockNum);

    constructor() {
        admin = msg.sender;
    }

    function createNewWill() external {
        require(!willOwners[msg.sender], "the account already owns 1 will");
        Will newWill = new Will(msg.sender);
        address newWillAddress = address(newWill);
        willLocation[newWillAddress] = willsAddresses.length;
        willsAddresses.push(newWillAddress);
        willsAddressesLength = willsAddresses.length;
        willOwners[msg.sender] = true;
        accountOwnsWill[msg.sender] = newWillAddress;
        emit newWillCreated(msg.sender, newWillAddress, block.number);
    }

    function destroyWill(address _willAddress) external {
        Will willToCheck = Will(payable(_willAddress));
        willOwners[willToCheck.willAdmin()] = false;
        willToCheck.terminateWill();

        if (willsAddressesLength > 1) {
            uint256 terminatedWillIndex = willLocation[_willAddress];
            if (terminatedWillIndex != (willsAddressesLength - 1)) {
                address lastwillAdress = willsAddresses[
                    willsAddressesLength - 1
                ];
                willsAddresses[terminatedWillIndex] = lastwillAdress;
                willLocation[lastwillAdress] = terminatedWillIndex;
            }
        }
        willsAddresses.pop();
        willsAddressesLength--;

        emit willTerminated(_willAddress, block.number);
    }
}
