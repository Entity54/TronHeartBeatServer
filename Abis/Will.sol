// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITRC20.sol";

contract Will {
    uint256 public lastCheckAtBlockNumber = 0;

    address public willAdmin; //will owner
    address public scAdmin; //The contract factory

    //ADMINISTRATOR ACCOUNT MANAGEMENT Track current admin accounts and TRC20 tokens these hold, to be transferred at Phase3
    address[] public adminAccounts; //registers all admin accounts that hold funds FirstAccount is called Main Account
    mapping(address => bool) public registeredAccounts; //checks if an account is registered
    mapping(address => uint256) public registeredAccountsBalance;

    address[] public assetsTRC20; //tracks hold of various assets the admin is holding
    mapping(address => bool) public registeredToken; //checks if a token is already registered
    mapping(address => mapping(address => bool)) public registeredAccountToken; //checks if a token is already registered for a specific account
    mapping(address => address[]) public registeredAccountHoldings; //which TRC20 tokens each account holds

    //GENERAL ACCOUNT MANAGEMENT
    mapping(address => mapping(address => uint256)) public clientBalances; //Kept for tracking administrator deposits/withdrawals for possible refunds

    bool public willState = false; //if true the will is active, else will is not active
    uint256 public willIssueBlockNum; //block Will was created at
    string public willGeneralMessage; //general message for will
    uint256 public trigger_dt1; //time in block numbers to triggers first check
    uint256 public trigger_dt2; //time in block numbers to triggers second check
    uint256 public trigger_dt3; //time in block numbers to triggers third check
    uint256 public lastCall_dt4; //time in block numbers to transfer funds to heirs after third check
    uint256 public triggerPoint1; //block number that first trigger will be sent
    uint256 public triggerPoint2; //block number that second trigger will be sent
    uint256 public triggerPoint3; //block number to transfer funds to sc
    uint256 public lastCallPoint; //block number that admin can still hit refund
    uint256 public distributionPoint; //block number to distribute funds to heirs
    uint256 public willStage; // 1 for first trigger poiint, 2 for 2nd and 3 for 3rd, 4 for Last Call

    //Details for any Will Neneficiary
    struct Will_Beneficiary {
        address beneficiaryAddress;
        string beneficiaryNickName;
        string finalMessage;
        uint256 cashPercent;
        uint256 index;
    }

    address[] public willBeneficiaries; //array with addresses of all beneficiaries
    mapping(address => Will_Beneficiary) public beneficiaries; //mapping for beneficiaries

    event Received(address, uint256);

    modifier onlyAdmin() {
        require(msg.sender == willAdmin, "action only for admin");
        _;
    }
    modifier onlySCAdmin() {
        //for selfdestruct
        require(msg.sender == scAdmin, "action only for scAdmin");
        _;
    }
    modifier onlyIfWillActive() {
        require(willState, "Will State is False");
        _;
    }

    event fundsDeposited(uint256 blockNum);
    event fundsDistributed(uint256 blockNum);

    constructor(address _willAdmin) {
        willAdmin = _willAdmin;
        scAdmin = msg.sender; //to be used for selfdestruct
    }

    function getAdminAccounts() public view returns (address[] memory) {
        return adminAccounts;
    }

    function getAssetsTRC20s() public view returns (address[] memory) {
        return assetsTRC20;
    }

    function getWillBeneficiaries() public view returns (address[] memory) {
        return willBeneficiaries;
    }

    function getBeneficiaryByAddress(address _beneficiaryAddress)
        external
        view
        returns (Will_Beneficiary memory)
    {
        return beneficiaries[_beneficiaryAddress];
    }

    function registerOwnerAccounts(address account) external {
        if (!registeredAccounts[account]) {
            adminAccounts.push(account);
            registeredAccounts[account] = true;
        }
    }

    function registerAccountTokens(address account, address tokenAddress)
        external
    {
        require(registeredAccounts[account], "acount is not registered");
        require(
            !registeredAccountToken[account][tokenAddress],
            "token is already registered for this account"
        );
        registeredAccountToken[account][tokenAddress] = true;
        registeredAccountHoldings[account].push(tokenAddress);

        if (!registeredToken[tokenAddress]) {
            registeredToken[tokenAddress] = true;
            assetsTRC20.push(tokenAddress);
        }
    }

    function getRegisteredAccountTokenAllowance(
        address account,
        address tokenAddress
    ) public view returns (uint256) {
        ITRC20 token = ITRC20(tokenAddress);
        return token.allowance(account, address(this));
    }

    function initiateWill(
        string memory message,
        uint256 _trigger_dt1,
        uint256 _trigger_dt2,
        uint256 _trigger_dt3,
        uint256 _lastCall_dt4
    ) external onlyAdmin {
        require(!willState, "willState is already true");
        willGeneralMessage = message;
        trigger_dt1 = _trigger_dt1;
        trigger_dt2 = _trigger_dt2;
        trigger_dt3 = _trigger_dt3;
        lastCall_dt4 = _lastCall_dt4;
        willStage = 0;
        willIssueBlockNum = block.number;
        triggerPoint1 = block.number + trigger_dt1;
        triggerPoint2 = triggerPoint1 + trigger_dt2;
        triggerPoint3 = triggerPoint2 + trigger_dt3;
        lastCallPoint = triggerPoint3 + lastCall_dt4;
        distributionPoint = lastCallPoint + 10;
        willState = true;
    }

    function addWillBeneficiary(
        address _beneficiaryAddress,
        string calldata _beneficiaryNickName,
        string calldata _finalMessage,
        uint256 _cashPercent
    ) external onlyAdmin {
        Will_Beneficiary memory newBeneficiary = Will_Beneficiary({
            beneficiaryAddress: _beneficiaryAddress,
            beneficiaryNickName: _beneficiaryNickName,
            finalMessage: _finalMessage,
            cashPercent: _cashPercent,
            index: willBeneficiaries.length
        });
        willBeneficiaries.push(_beneficiaryAddress);
        beneficiaries[_beneficiaryAddress] = newBeneficiary;
    }

    function amendWillBeneficiary(
        address _beneficiaryAddress,
        string calldata _beneficiaryNickName,
        string calldata _finalMessage,
        uint256 _cashPercent
    ) external onlyAdmin {
        if (
            keccak256(
                bytes(beneficiaries[_beneficiaryAddress].beneficiaryNickName)
            ) != keccak256(bytes(_beneficiaryNickName))
        ) {
            beneficiaries[_beneficiaryAddress]
                .beneficiaryNickName = _beneficiaryNickName;
        }
        if (
            keccak256(bytes(beneficiaries[_beneficiaryAddress].finalMessage)) !=
            keccak256(bytes(_finalMessage))
        ) {
            beneficiaries[_beneficiaryAddress].finalMessage = _finalMessage;
        }
        if (beneficiaries[_beneficiaryAddress].cashPercent != _cashPercent) {
            beneficiaries[_beneficiaryAddress].cashPercent = _cashPercent;
        }
    }

    function removeWillBeneficiary(address _beneficiaryAddress)
        external
        onlyAdmin
    {
        Will_Beneficiary memory currentBeneficiary = beneficiaries[
            _beneficiaryAddress
        ];
        if (currentBeneficiary.beneficiaryAddress != address(0)) {
            //beneficary exists
            uint256 numOfBeneficiaries = willBeneficiaries.length;
            if (numOfBeneficiaries > 1) {
                uint256 indx = currentBeneficiary.index;
                if (indx != (willBeneficiaries.length - 1)) {
                    address lastBeneficiaryAdress = willBeneficiaries[
                        willBeneficiaries.length - 1
                    ];
                    willBeneficiaries[indx] = lastBeneficiaryAdress;
                    beneficiaries[lastBeneficiaryAdress].index = indx;
                }
            }
            willBeneficiaries.pop();
            delete beneficiaries[_beneficiaryAddress];
        }
    }

    //in production this sould be private
    function depositFunds() public {
        for (uint256 i = 0; i < adminAccounts.length; i++) {
            address acc = adminAccounts[i];
            for (
                uint256 j = 0;
                j < registeredAccountHoldings[acc].length;
                j++
            ) {
                address tokenAddress = registeredAccountHoldings[acc][j];
                ITRC20 token = ITRC20(tokenAddress);
                uint256 amount = token.balanceOf(acc);
                if (amount > 0) {
                    token.transferFrom(acc, address(this), amount);
                    clientBalances[tokenAddress][acc] += amount; //in case we want refund
                }
            }
        }

        emit fundsDeposited(block.number);
    }

    function refundFunds() public {
        for (uint256 i = 0; i < adminAccounts.length; i++) {
            address acc = adminAccounts[i];
            for (
                uint256 j = 0;
                j < registeredAccountHoldings[acc].length;
                j++
            ) {
                address tokenAddress = registeredAccountHoldings[acc][j];
                ITRC20 token = ITRC20(tokenAddress);
                uint256 amount = clientBalances[tokenAddress][acc];
                if (amount > 0) {
                    clientBalances[tokenAddress][acc] -= amount;
                    token.transfer(acc, amount);
                }
            }
        }
    }

    //Check block.number vs TriggerPoints and Last call and set Will Stage
    function checkWillStage() external returns (uint256) {
        lastCheckAtBlockNumber = block.number;

        if (block.number > distributionPoint && willStage == 5) {
            willStage = 6;
        } else if (block.number > distributionPoint && willStage < 5) {
            willStage = 5;
            willState = false;
            releaseWill();
        } else if (block.number > lastCallPoint && willStage < 4) {
            willStage = 4;
            depositFunds(); //The time has arrived to pull all registered tokens of registered account to this sc
        } else if (block.number > triggerPoint3 && willStage < 3) {
            willStage = 3;
        } else if (block.number > triggerPoint2 && willStage < 2) {
            willStage = 2;
        } else if (block.number > triggerPoint1 && willStage < 1) {
            willStage = 1;
        }

        return willStage;
    }

    //when called resets triggerPoints and willStage
    function renewWillTriggers() private {
        triggerPoint1 = block.number + trigger_dt1;
        triggerPoint2 = triggerPoint1 + trigger_dt2;
        triggerPoint3 = triggerPoint2 + trigger_dt3;
        lastCallPoint = triggerPoint3 + lastCall_dt4;
        distributionPoint = lastCallPoint + 5;
        willStage = 0; //revert back to stage 0
    }

    //This to be called by the willAdmin to renew will intervals manually
    function aliveAndKicking() public onlyAdmin onlyIfWillActive {
        if (willStage == 4) {
            refundFunds(); //send tokens back to admin accounts
        }

        renewWillTriggers();
    }

    //This can be called periodically.
    function checkAdminBalance() public onlyIfWillActive returns (bool) {
        require(msg.sender != willAdmin, "action not for admin");

        //cycle thorugh all admin accounts
        bool adminBalanceDecreased = false;
        uint256 i = 0;
        while (i < adminAccounts.length && !adminBalanceDecreased) {
            address adminAcc = adminAccounts[i];
            uint256 freshAdminBalance = adminAcc.balance;

            if (
                freshAdminBalance < registeredAccountsBalance[adminAcc]
            ) //alive and signing transactions
            {
                adminBalanceDecreased = true;
                registeredAccountsBalance[adminAcc] = freshAdminBalance;
            } else if (
                freshAdminBalance > registeredAccountsBalance[adminAcc]
            ) {
                registeredAccountsBalance[adminAcc] = freshAdminBalance;
            }

            i++;
        }

        // willAdmin  checks in case willAdmin is not one of the registered accounts
        uint256 freshWillAdminBalance = willAdmin.balance;
        if (
            freshWillAdminBalance < registeredAccountsBalance[willAdmin]
        ) //alive and signing transactions
        {
            adminBalanceDecreased = true;
            registeredAccountsBalance[willAdmin] = freshWillAdminBalance;
        } else if (
            freshWillAdminBalance > registeredAccountsBalance[willAdmin]
        ) {
            registeredAccountsBalance[willAdmin] = freshWillAdminBalance;
        }

        if (adminBalanceDecreased) {
            renewWillTriggers();
        }

        return adminBalanceDecreased;
    }

    function releaseWill() private {
        for (uint256 j = 0; j < assetsTRC20.length; j++) {
            uint256 distributedCash = 0;
            ITRC20 distributedToken = ITRC20(assetsTRC20[j]);
            uint256 amount = distributedToken.balanceOf(address(this));

            //Distribute Tokens
            for (uint256 i = 0; i < willBeneficiaries.length; i++) {
                address bfAddress = willBeneficiaries[i];
                Will_Beneficiary memory bfStruct = beneficiaries[bfAddress];

                //SEND CASH TO ACCOUNTS
                if (bfStruct.cashPercent > 0) {
                    uint256 cashAmount;
                    if (i < (willBeneficiaries.length - 1)) {
                        cashAmount = (amount / 100) * (bfStruct.cashPercent);
                        distributedCash += cashAmount;
                    } else {
                        cashAmount = amount - distributedCash;
                    }

                    if (cashAmount > 0) {
                        distributedToken.transfer(bfAddress, cashAmount);
                    }
                }
            }
        }

        // delete beneficiaries[bfAddress];
        // willBeneficiaries = new address[](0);
        emit fundsDistributed(block.number);
    }

    function cleanUp() public {
        willGeneralMessage = "";
        trigger_dt1 = 0;
        trigger_dt2 = 0;
        trigger_dt3 = 0;
        lastCall_dt4 = 0;
        willIssueBlockNum = 0;
        triggerPoint1 = 0;
        triggerPoint2 = 0;
        triggerPoint3 = 0;
        lastCallPoint = 0;
        distributionPoint = 0;

        //delete adminAccounts
        for (uint256 i = 0; i < adminAccounts.length; i++) {
            address accAddr = adminAccounts[i];
            registeredAccounts[accAddr] = false;
        }
        adminAccounts = new address[](0);

        //delete willBeneficiaries
        for (uint256 i = 0; i < willBeneficiaries.length; i++) {
            address accAddr = willBeneficiaries[i];
            delete beneficiaries[accAddr];
        }
        willBeneficiaries = new address[](0);
    }

    function voidWill() external onlyAdmin onlyIfWillActive {
        //transfer out any funds back to the Admin registered accounts
        refundFunds();

        //reset to intial conditions
        willState = false;
        cleanUp();
    }

    function terminateWill() external onlySCAdmin {
        if (!willState) {
            selfdestruct(payable(scAdmin));
        }
    }
}
