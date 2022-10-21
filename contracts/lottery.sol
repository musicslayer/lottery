// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.17;

// The lottery contract is not a token. We only use the IERC20 interface so that any tokens sent to this contract can be accessed.

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol"
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// Chainlink VRF contracts.

// import "@chainlink/contracts/src/v0.8/interfaces/LinkTokenInterface.sol";
interface LinkTokenInterface {
    function allowance(address owner, address spender) external view returns (uint256 remaining);
    function approve(address spender, uint256 value) external returns (bool success);
    function balanceOf(address owner) external view returns (uint256 balance);
    function decimals() external view returns (uint8 decimalPlaces);
    function decreaseApproval(address spender, uint256 addedValue) external returns (bool success);
    function increaseApproval(address spender, uint256 subtractedValue) external;
    function name() external view returns (string memory tokenName);
    function symbol() external view returns (string memory tokenSymbol);
    function totalSupply() external view returns (uint256 totalTokensIssued);
    function transfer(address to, uint256 value) external returns (bool success);
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool success);
    function transferFrom(address from, address to, uint256 value) external returns (bool success);
}

// import "@chainlink/contracts/src/v0.8/interfaces/VRFV2WrapperInterface.sol";
interface VRFV2WrapperInterface {
    function lastRequestId() external view returns (uint256);
    function calculateRequestPrice(uint32 _callbackGasLimit) external view returns (uint256);
    function estimateRequestPrice(uint32 _callbackGasLimit, uint256 _requestGasPriceWei) external view returns (uint256);
}

// import "@chainlink/contracts/src/v0.8/VRFV2WrapperConsumerBase.sol";
abstract contract VRFV2WrapperConsumerBase {
    LinkTokenInterface internal immutable LINK;
    VRFV2WrapperInterface internal immutable VRF_V2_WRAPPER;

    constructor(address _link, address _vrfV2Wrapper) {
        LINK = LinkTokenInterface(_link);
        VRF_V2_WRAPPER = VRFV2WrapperInterface(_vrfV2Wrapper);
    }

    function requestRandomness(uint32 _callbackGasLimit, uint16 _requestConfirmations, uint32 _numWords) internal returns (uint256 requestId) {
        LINK.transferAndCall(address(VRF_V2_WRAPPER), VRF_V2_WRAPPER.calculateRequestPrice(_callbackGasLimit), abi.encode(_callbackGasLimit, _requestConfirmations, _numWords));
        return VRF_V2_WRAPPER.lastRequestId();
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal virtual;

    function rawFulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) external {
        require(msg.sender == address(VRF_V2_WRAPPER), "only VRF V2 wrapper can fulfill");
        fulfillRandomWords(_requestId, _randomWords);
    }
}

/**
 * @title The Musicslayer Lottery
 * @author Musicslayer
 */
contract MusicslayerLottery is VRFV2WrapperConsumerBase {
    /*
    *
    *
        Errors
    *
    *
    */

    /// @notice Withdrawing any Chainlink would violate the minimum reserve requirement.
    error ChainlinkMinimumReserveError(uint requestedValue, uint chainlinkBalance, uint chainlinkMinimumReserve);

    /// @notice The requestId of the VRF request does not match the requestId of the callback.
    error ChainlinkVRFRequestIdMismatch(uint callbackRequestId, uint expectedRequestId);

    /// @notice The VRF request was initiated during a previous lottery.
    error ChainlinkVRFRequestStale(uint requestLotteryNumber, uint currentLotteryNumber);

    /// @notice This contract is corrupt.
    error CorruptContractError();

    /// @notice Drawing a winning ticket is not allowed at this time.
    error DrawWinningTicketError();

    /// @notice This contract does not have the funds requested.
    error InsufficientFundsError(uint requestedValue, uint contractBalance);

    /// @notice The current lottery is active and is not ready to be ended.
    error LotteryActiveError();

    /// @notice The current lottery is not active and tickets purchases are not allowed.
    error LotteryInactiveError();

    /// @notice This transaction is purchasing too many tickets.
    error MaxTicketPurchaseError(uint requestedTicketPurchase, uint maxTicketPurchase);

    /// @notice A winning ticket has not been drawn yet.
    error NoWinningTicketDrawnError();

    /// @notice This contract is not corrupt.
    error NotCorruptContractError();

    /// @notice The calling address is not the operator.
    error NotOperatorError(address _address, address operatorAddress);

    /// @notice The calling address is not the contract owner.
    error NotOwnerError(address _address, address ownerAddress);

    /// @notice The calling address is not an eligible player.
    error NotPlayerError(address _address);

    /// @notice The required penalty has not been paid.
    error PenaltyNotPaidError(uint value, uint penalty);

    /// @notice The self-destruct is not ready.
    error SelfDestructNotReadyError();

    /// @notice The token contract could not be found.
    error TokenContractError(address tokenAddress);

    /// @notice The token transfer failed.
    error TokenTransferError(address tokenAddress, address _address, uint requestedValue);

    /// @notice A winning ticket has already been drawn.
    error WinningTicketDrawnError();
    
    /*
    *
    *
        Events
    *
    *
    */

    /// @notice A record of the contract becoming corrupt.
    event Corruption(uint indexed blockNumber);

    /// @notice A record of the contract becoming uncorrupt.
    event CorruptionReset(uint indexed blockNumber);

    /// @notice A record of a lottery being canceled.
    event LotteryCancel(uint indexed lotteryNumber, uint indexed lotteryBlockNumberStart);

    /// @notice A record of a lottery ending.
    event LotteryEnd(uint indexed lotteryNumber, uint indexed lotteryBlockNumberStart, address indexed winningAddress, uint winnerPrize);

    /// @notice A record of a lottery starting.
    event LotteryStart(uint indexed lotteryNumber, uint indexed lotteryBlockNumberStart, uint indexed lotteryBlockDuration, uint ticketPrice);

    /// @notice A record of the operator address changing.
    event OperatorChanged(address indexed oldOperatorAddress, address indexed newOperatorAddress);

    /// @notice A record of the owner address changing.
    event OwnerChanged(address indexed oldOwnerAddress, address indexed newOwnerAddress);

    /// @notice A record of a winning ticket being drawn.
    event WinningTicketDrawn(uint indexed winningTicket, uint indexed totalTickets);

    /*
    *
    *
        Constants
    *
    *
    */

    /*
        Lottery
    */

    // The grace period that everyone has to withdraw their funds before the owner can destroy a corrupt contract.
    uint private constant CORRUPT_CONTRACT_GRACE_PERIOD_BLOCKS = 864_000; // About 30 days.

    // This is the maximum number of tickets that can be purchased in a single transaction.
    // Note that players can use additional transactions to purchase more tickets.
    uint private constant MAX_TICKET_PURCHASE = 10_000;
    
    // An integer between 0 and 100 representing the percentage of the "playerPrizePool" amount that the operator takes every game.
    // Note that the player always receives the entire "bonusPrizePool" amount.
    uint private constant OPERATOR_CUT = 10;

    /*
        Chainlink
    */

    uint32 private constant CHAINLINK_CALLBACK_GAS_LIMIT = 200_000; // This was chosen experimentally.
    uint private constant CHAINLINK_MINIMUM_RESERVE = 40 * 10 ** CHAINLINK_TOKEN_DECIMALS; // 40 LINK
    uint16 private constant CHAINLINK_REQUEST_CONFIRMATION_BLOCKS = 200; // About 10 minutes. Use the maximum allowed value of 200 blocks to be extra secure.
    uint16 private constant CHAINLINK_REQUEST_RETRY_BLOCKS = 600; // About 30 minutes. If we request a random number but don't get it after 600 blocks, we can make a new request.
    uint private constant CHAINLINK_RETRY_MAX = 10;
    address private constant CHAINLINK_TOKEN_ADDRESS = 0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06;
    uint private constant CHAINLINK_TOKEN_DECIMALS = 18;
    address private constant CHAINLINK_WRAPPER_ADDRESS = 0x699d428ee890d55D56d5FC6e26290f3247A762bd;

    /*
    *
    *
        Private Variables
    *
    *
    */
    
    // A lock variable to prevent reentrancy. Note that the lock is global, so a function using the lock cannot call another function that is also using the lock.
    bool private lockFlag;

    // If the contract is in a bad state, the owner is allowed to take emergency actions. This is designed to allow emergencies to be remedied without allowing anyone to steal the contract funds.
    // Currently, the only known possible bad state would be caused by Chainlink being permanently down.
    bool private corruptContractFlag;
    uint private corruptContractBlockNumber;
    
    // The current lottery number.
    uint private lotteryNumber;

    // Block number where the lottery started.
    uint private lotteryBlockNumberStart;

    // The number of blocks where the lottery is active and players may purchase tickets.
    // If the amount is changed, the new amount will only apply to future lotteries, not the current one.
    uint private lotteryActiveBlocks;
    uint private currentLotteryActiveBlocks;

    // The owner is the original operator and is able to assign themselves the operator role at any time.
    address private ownerAddress;

    // The operator is responsible for running the lottery. In return, they will receive a cut of each prize.
    address private operatorAddress;

    // The price of each ticket. If the price is changed, the new price will only apply to future lotteries, not the current one.
    uint private ticketPrice;
    uint private currentTicketPrice;

    /* To ensure the safety of player funds, the contract balance is accounted for by splitting it into different places:
        // contractFunds - The general funds owned by the contract. The operator can add or withdraw funds at will.
        // playerPrizePool - The funds players have paid to purchase tickets. The operator cannot add or withdraw funds.
        // bonusPrizePool - The funds that have optionally been added to "sweeten the pot" and provide a bigger prize. The operator can add funds but cannot withdraw them.
        // claimableBalancePool - The funds that have not yet been claimed. The operator takes their cut from here, but otherwise they cannot add or withdraw funds.
        // refundPool - The funds that were in the playerPrizePool for a lottery that was canceled. Players can manually request refunds for any tickets they have purchased.
       Anything else not accounted for is considered to be "extra" funds that are treated the same as contract funds.
    */
    uint private contractFunds;
    uint private playerPrizePool;
    uint private bonusPrizePool;
    uint private claimableBalancePool;
    uint private refundPool;

    // Variables to keep track of who is playing and how many tickets they have.
    uint private currentTicketNumber;
    mapping(uint => address) private map_ticket2Address;
    mapping(uint => mapping(address => uint)) private map_lotteryNum2Address2NumTickets;
    mapping(uint => bool) private map_lotteryNum2IsRefundable;

    // Mapping of addresses to claimable balances.
    // For players, this balance is from winnings or from leftover funds after purchasing tickets.
    // For the operator, this balance is from their cut of the prize.
    mapping(address => uint) private map_address2ClaimableBalance;

    // Mappings that show the winning addresses and prizes for each lottery.
    mapping(uint => address) private map_lotteryNum2WinningAddress;
    mapping(uint => uint) private map_lotteryNum2WinnerPrize;

    // Chainlink token and VRF info.
    uint private chainlinkRetryCounter;
    
    bool private chainlinkRequestIdFlag;
    uint private chainlinkRequestIdBlockNumber;
    uint private chainlinkRequestIdLotteryNumber;
    uint private chainlinkRequestId;

    bool private winningTicketFlag;
    uint private winningTicket;

    /*
    *
    *
        Contract Functions
    *
    *
    */

    /*
        Built-In Functions
    */

    constructor(uint initialLotteryActiveBlocks, uint initialTicketPrice) VRFV2WrapperConsumerBase(CHAINLINK_TOKEN_ADDRESS, CHAINLINK_WRAPPER_ADDRESS) payable {
        addContractFunds(msg.value);

        setOwnerAddress(msg.sender);
        setOperatorAddress(msg.sender);

        lotteryActiveBlocks = initialLotteryActiveBlocks;
        ticketPrice = initialTicketPrice;

        startNewLottery();
    }

    fallback() external payable {
        // There is no legitimate reason for this fallback function to be called.
        punish();
    }

    receive() external payable {
        // Funds received from a player will be used to buy tickets. Funds received from the operator will be counted as contract funds.
        lock();

        if(isOperatorAddress(msg.sender)) {
            addContractFunds(msg.value);
        }
        else {
            requireLotteryActive();
            requireNotCorruptContract();

            buyTickets(msg.sender, msg.value);
        }

        unlock();
    }

    /*
        Action Functions
    */

    function buyTickets(address _address, uint value) private {
        // Purchase as many tickets as possible for the address with the provided value. Note that tickets can only be purchased in whole number quantities.
        // After spending all the funds on tickets, anything left over will be added to the address's claimable balance.
        uint numTickets = value / currentTicketPrice;
        if(numTickets > MAX_TICKET_PURCHASE) {
            revert MaxTicketPurchaseError(numTickets, MAX_TICKET_PURCHASE);
        }

        uint totalTicketValue = numTickets * currentTicketPrice;
        uint unspentValue = value - totalTicketValue;

        addPlayerPrizePool(totalTicketValue);
        addAddressClaimableBalance(_address, unspentValue);
        
        // To save gas, only write the information for the first purchased ticket, and then every 100 afterwards.
        uint lastTicketNumber = currentTicketNumber + numTickets;
        for(uint i = currentTicketNumber; i < lastTicketNumber; i += 100) {
            map_ticket2Address[i] = _address;
        }

        map_lotteryNum2Address2NumTickets[lotteryNumber][_address] += numTickets;
        currentTicketNumber = lastTicketNumber;
    }

    function cancelCurrentLottery(uint value) private {
        // Mark the current lottery as refundable and start a new lottery.
        map_lotteryNum2IsRefundable[lotteryNumber] = true;
        emit LotteryCancel(lotteryNumber, lotteryBlockNumberStart);

        // Move funds in the player prize pool to the refund pool. Players who have purchased tickets may request a refund manually.
        addRefundPool(playerPrizePool);
        playerPrizePool = 0;

        // Carry over the existing bonus prize pool and add in the penalty value.
        addBonusPrizePool(value);

        // For recordkeeping purposes, the winner is the zero address and the prize is zero.
        map_lotteryNum2WinningAddress[lotteryNumber] = address(0);
        map_lotteryNum2WinnerPrize[lotteryNumber] = 0;

        startNewLottery();
    }

    function drawWinningTicket() private {
        if(winningTicketFlag || (chainlinkRequestIdFlag && !isRetryPermitted())) {
            revert DrawWinningTicketError();
        }

        // At a certain point we must conclude that Chainlink is down and give up. Don't allow for additional attempts because they cost Chainlink tokens.
        if(chainlinkRetryCounter > CHAINLINK_RETRY_MAX) {
            setCorruptContract(true);
            return;
        }

        if(isZeroPlayerGame() || isOnePlayerGame()) {
            // Don't bother paying Chainlink since we don't need a random number anyway.
            recordWinningTicket(0);
        }
        else {
            chainlinkRetryCounter++;
            chainlinkRequestIdFlag = true;
            chainlinkRequestIdBlockNumber = block.number;
            chainlinkRequestIdLotteryNumber = lotteryNumber;
            chainlinkRequestId = requestRandomness(CHAINLINK_CALLBACK_GAS_LIMIT, CHAINLINK_REQUEST_CONFIRMATION_BLOCKS, 1);
        }
    }

    function endCurrentLottery() private {
        // End the current lottery, credit any prizes rewarded, and then start a new lottery.
        address winningAddress;
        uint operatorPrize;
        uint winnerPrize;

        if(isZeroPlayerGame()) {
            // No one played. For recordkeeping purposes, the winner is the zero address and the prize is zero.
        }
        else if(isOnePlayerGame()) {
            // Since only one person has played, just give them the entire prize.
            winningAddress = map_ticket2Address[0];
            winnerPrize = bonusPrizePool + playerPrizePool;
        }
        else {
            // Give the lottery operator their cut of the pot, and then give the rest to the randomly chosen winner.
            winningAddress = findWinningAddress(winningTicket);
            operatorPrize = playerPrizePool * OPERATOR_CUT / 100;
            winnerPrize = playerPrizePool + bonusPrizePool - operatorPrize;
        }

        addAddressClaimableBalance(getOperatorAddress(), operatorPrize);
        addAddressClaimableBalance(winningAddress, winnerPrize);

        playerPrizePool = 0;
        bonusPrizePool = 0;

        map_lotteryNum2WinningAddress[lotteryNumber] = winningAddress;
        map_lotteryNum2WinnerPrize[lotteryNumber] = winnerPrize;

        emit LotteryEnd(lotteryNumber, lotteryBlockNumberStart, winningAddress, winnerPrize);

        startNewLottery();
    }

    /*
        Helper Functions
    */

    function findWinningAddress(uint ticket) private view returns (address) {
        address winningAddress = map_ticket2Address[ticket];

        // Because "map_ticket2Address" potentially has gaps, we may have to search until we find the winning address.
        // Note that because of the way "map_ticket2Address" is filled in, element 0 is guaranteed to have a nonzero address.
        while(winningAddress == address(0)) {
            winningAddress = map_ticket2Address[--ticket];
        }

        return winningAddress;
    }

    function fulfillRandomWords(uint requestId, uint[] memory randomWords) internal override {
        // This is the Chainlink VRF callback that will give us the random number we requested.
        // We use this to choose a winning ticket if at least two players have entered the lottery.
        if(chainlinkRequestId != requestId) {
            revert ChainlinkVRFRequestIdMismatch(requestId, chainlinkRequestId);
        }

        if(chainlinkRequestIdLotteryNumber != lotteryNumber) {
            revert ChainlinkVRFRequestStale(chainlinkRequestIdLotteryNumber, lotteryNumber);
        }

        recordWinningTicket(randomWords[0] % currentTicketNumber);
    }

    function recordWinningTicket(uint _winningTicket) private {
        winningTicketFlag = true;
        winningTicket = _winningTicket;
        emit WinningTicketDrawn(_winningTicket, currentTicketNumber);
    }

    function startNewLottery() private {
        // Reset lottery state and begin a new lottery. The contract is designed so that we don't need to clear any of the mappings, something that saves a lot of gas.
        currentTicketNumber = 0;

        // If any of these values have been changed by the operator, update them now before starting the next lottery.
        currentLotteryActiveBlocks = lotteryActiveBlocks;
        currentTicketPrice = ticketPrice;

        lotteryNumber++;
        lotteryBlockNumberStart = block.number;

        chainlinkRetryCounter = 0;
        chainlinkRequestIdFlag = false;
        winningTicketFlag = false;

        emit LotteryStart(lotteryNumber, lotteryBlockNumberStart, lotteryActiveBlocks, ticketPrice);
    }

    /*
        Add Functions
    */

    function addAddressClaimableBalance(address _address, uint value) private {
        map_address2ClaimableBalance[_address] += value;
        claimableBalancePool += value;
    }

    function addBonusPrizePool(uint value) private {
        bonusPrizePool += value;
    }

    function addContractFunds(uint value) private {
        contractFunds += value;
    }

    function addPlayerPrizePool(uint value) private {
        playerPrizePool += value;
    }

    function addRefundPool(uint value) private {
        refundPool += value;
    }

    /*
        Withdraw Functions
    */

    function withdrawAddressClaimableBalance(address _address) private {
        // We only allow the entire balance to be withdrawn.
        uint balance = getAddressClaimableBalance(_address);

        map_address2ClaimableBalance[_address] = 0;
        claimableBalancePool -= balance;

        transferToAddress(_address, balance);
    }

    function withdrawAddressRefund(uint _lotteryNumber, address _address) private {
        // We only allow the entire balance to be withdrawn.
        uint balance = getAddressRefund(_lotteryNumber, _address);

        map_lotteryNum2Address2NumTickets[_lotteryNumber][_address] = 0;
        refundPool -= balance;

        transferToAddress(_address, balance);
    }

    function withdrawAllChainlinkBalance(address _address) private {
        // Withdraw all Chainlink, including the minimum reserve.
        _withdrawTokens(CHAINLINK_TOKEN_ADDRESS, _address, getTokenBalance(CHAINLINK_TOKEN_ADDRESS), true);
    }

    function withdrawAllTokenBalance(address tokenAddress, address _address) private {
        _withdrawTokens(tokenAddress, _address, getTokenBalance(tokenAddress), false);
    }

    function withdrawAllContractFunds(address _address) private {
        // Withdraw the entire contract funds. For the purposes of this function, extra funds are treated as contract funds.
        contractFunds = 0;
        transferToAddress(_address, getOperatorContractBalance());
    }

    function withdrawChainlinkBalance(address _address, uint value) private {
        // Withdraw any amount of Chainlink, including the minimum reserve.
        _withdrawTokens(CHAINLINK_TOKEN_ADDRESS, _address, value, true);
    }

    function withdrawContractFunds(address _address, uint value) private {
        // Withdraw an amount from the contract funds. For the purposes of this function, extra funds are treated as contract funds.
        uint operatorContractBalance = getOperatorContractBalance();

        if(value > operatorContractBalance) {
            revert InsufficientFundsError(value, operatorContractBalance);
        }

        // Only if the value is higher than the extra funds do we subtract from "contractFunds". This accounting makes it so extra funds are spent first.
        if(value > getExtraContractBalance()) {
            contractFunds -= (value - getExtraContractBalance());
        }
        transferToAddress(_address, value);
    }

    function withdrawTokenBalance(address tokenAddress, address _address, uint value) private {
        _withdrawTokens(tokenAddress, _address, value, false);
    }

    function _withdrawTokens(address tokenAddress, address _address, uint value, bool bypassReserve) private {
        // For Chainlink, we may have to honor the minimum reserve requirement.
        if(tokenAddress == CHAINLINK_TOKEN_ADDRESS && !bypassReserve) {
            uint tokenBalance = getTokenBalance(tokenAddress);

            if(tokenBalance < CHAINLINK_MINIMUM_RESERVE) {
                revert ChainlinkMinimumReserveError(value, tokenBalance, CHAINLINK_MINIMUM_RESERVE);
            }
            else {
                uint allowedValue = tokenBalance - CHAINLINK_MINIMUM_RESERVE;
                if(allowedValue < value) {
                    revert ChainlinkMinimumReserveError(value, tokenBalance, CHAINLINK_MINIMUM_RESERVE);
                }
            }
        }

        tokenTransferToAddress(tokenAddress, _address, value);
    }

    /*
        Query Functions
    */

    function isAddressPlaying(address _address) private view returns (bool) {
        return map_lotteryNum2Address2NumTickets[lotteryNumber][_address] != 0;
    }

    function isCorruptContract() private view returns (bool) {
        return corruptContractFlag;
    }

    function isCorruptContractGracePeriod() private view returns (bool) {
        return getRemainingCorruptContractGracePeriodBlocks() > 0;
    }

    function isLocked() private view returns (bool) {
        return lockFlag;
    }

    function isLotteryActive() private view returns (bool) {
        return getRemainingLotteryActiveBlocks() > 0;
    }

    function isOnePlayerGame() private view returns (bool) {
        // Check to see if there is only one player who has purchased all the tickets.
        return currentTicketNumber != 0 && (getTotalAddressTickets(map_ticket2Address[0]) == getTotalTickets());
    }

    function isOperatorAddress(address _address) private view returns (bool) {
        return _address == getOperatorAddress();
    }

    function isOwnerAddress(address _address) private view returns (bool) {
        return _address == getOwnerAddress();
    }

    function isPlayerAddress(address _address) private view returns (bool) {
        // The only ineligible player is the operator.
        return _address != getOperatorAddress();
    }

    function isRetryPermitted() private view returns (bool) {
        // We allow for a redraw if the random number has not been received after a certain number of blocks. This would be needed if Chainlink ever experiences an outage.
        return block.number - chainlinkRequestIdBlockNumber > CHAINLINK_REQUEST_RETRY_BLOCKS;
    }

    function isSelfDestructReady() private view returns (bool) {
        // If this function returns true, the owner is allowed to call "selfdestruct" and withdraw the entire contract balance.
        // To ensure the owner cannot just run away with prize funds, we require all of the following to be true:
        // -> The contract must be corrupt.
        // -> After the contract became corrupt, the owner must wait for a grace period to pass. This gives everyone a chance to withdraw any funds owed to them.
        return isCorruptContract() && !isCorruptContractGracePeriod();
    }

    function isWinningTicketDrawn() private view returns (bool) {
        return winningTicketFlag;
    }

    function isZeroPlayerGame() private view returns (bool) {
        // Check to see if there are no players.
        return currentTicketNumber == 0;
    }

    /*
        Require Functions
    */

    function requireCorruptContract() private view {
        if(!isCorruptContract()) {
            revert NotCorruptContractError();
        }
    }

    function requireLotteryActive() private view {
        if(!isLotteryActive()) {
            revert LotteryInactiveError();
        }
    }

    function requireLotteryInactive() private view {
        if(isLotteryActive()) {
            revert LotteryActiveError();
        }
    }

    function requireNoWinningTicketDrawn() private view {
        if(isWinningTicketDrawn()) {
            revert WinningTicketDrawnError();
        }
    }

    function requireNotCorruptContract() private view {
        if(isCorruptContract()) {
            revert CorruptContractError();
        }
    }

    function requireOperatorAddress(address _address) private view {
        if(!isOperatorAddress(_address)) {
            revert NotOperatorError(_address, getOperatorAddress());
        }
    }

    function requireOwnerAddress(address _address) private view {
        if(!isOwnerAddress(_address)) {
            revert NotOwnerError(_address, getOwnerAddress());
        }
    }

    function requirePenaltyPayment(uint value) private view {
        if(value < getPenaltyPayment()) {
            revert PenaltyNotPaidError(value, getPenaltyPayment());
        }
    }

    function requirePlayerAddress(address _address) private view {
        if(!isPlayerAddress(_address)) {
            revert NotPlayerError(_address);
        }
    }

    function requireSelfDestructReady() private view {
        if(!isSelfDestructReady()) {
            revert SelfDestructNotReadyError();
        }
    }

    function requireWinningTicketDrawn() private view {
        if(!isWinningTicketDrawn()) {
            revert NoWinningTicketDrawnError();
        }
    }

    /*
        Get Functions
    */

    function getAccountedContractBalance() private view returns (uint) {
        return contractFunds + playerPrizePool + bonusPrizePool + claimableBalancePool + refundPool;
    }

    function getAddressClaimableBalance(address _address) private view returns (uint) {
        return map_address2ClaimableBalance[_address];
    }

    function getAddressRefund(uint _lotteryNumber, address _address) private view returns (uint) {
        if(map_lotteryNum2IsRefundable[_lotteryNumber]) {
            return map_lotteryNum2Address2NumTickets[_lotteryNumber][_address];
        }
        else {
            // The lottery was not canceled so no one can get a refund.
            return 0;
        }
    }

    function getAddressWinChance(address _address, uint N) private view returns (uint) {
        return getTotalAddressTickets(_address) * N / getTotalTickets();
    }

    function getBonusPrizePool() private view returns (uint) {
        return bonusPrizePool;
    }

    function getClaimableBalancePool() private view returns (uint) {
        return claimableBalancePool;
    }

    function getContractBalance() private view returns (uint) {
        // This is the true and complete contract balance.
        return address(this).balance;
    }

    function getContractFunds() private view returns (uint) {
        return contractFunds;
    }

    function getExtraContractBalance() private view returns (uint) {
        // Returns the amount of "extra" funds this contract has. This should usually be zero, but may be more if funds are sent here in ways that cannot be accounted for.
        // For example, a coinbase transaction or another contract calling "selfdestruct" could send funds here without passing through the "receive" function for proper accounting.
        return getContractBalance() - getAccountedContractBalance();
    }

    function getLotteryActiveBlocks() private view returns (uint) {
        return currentLotteryActiveBlocks;
    }

    function getLotteryBlockNumberStart() private view returns (uint) {
        return lotteryBlockNumberStart;
    }

    function getLotteryNumber() private view returns (uint) {
        return lotteryNumber;
    }

    function getLotteryWinnerPrize(uint _lotteryNumber) private view returns (uint) {
        return map_lotteryNum2WinnerPrize[_lotteryNumber];
    }

    function getLotteryWinningAddress(uint _lotteryNumber) private view returns (address) {
        return map_lotteryNum2WinningAddress[_lotteryNumber];
    }

    function getOperatorAddress() private view returns (address) {
        return operatorAddress;
    }

    function getOperatorContractBalance() private view returns (uint) {
        return contractFunds + getExtraContractBalance();
    }

    function getOwnerAddress() private view returns (address) {
        return ownerAddress;
    }

    function getPenaltyPayment() private view returns (uint) {
        // The base penalty is 0.1 of the native coin, but if the lottery is inactive and there are at least two players, then the penalty is multiplied by 5.
        uint penalty = 0.1 ether;
        if(!isLotteryActive() && !isZeroPlayerGame() && !isOnePlayerGame()) {
            penalty *= 5;
        }
        return penalty;
    }

    function getPlayerPrizePool() private view returns (uint) {
        return playerPrizePool;
    }

    function getRefundPool() private view returns (uint) {
        return refundPool;
    }

    function getRemainingCorruptContractGracePeriodBlocks() private view returns (uint) {
        uint numBlocksPassed = block.number - corruptContractBlockNumber;
        if(numBlocksPassed <= CORRUPT_CONTRACT_GRACE_PERIOD_BLOCKS) {
            return CORRUPT_CONTRACT_GRACE_PERIOD_BLOCKS - numBlocksPassed;
        }
        else {
            return 0;
        }
    }

    function getRemainingLotteryActiveBlocks() private view returns (uint) {
        uint numBlocksPassed = block.number - lotteryBlockNumberStart;
        if(numBlocksPassed <= currentLotteryActiveBlocks) {
            return currentLotteryActiveBlocks - numBlocksPassed;
        }
        else {
            return 0;
        }
    }

    function getTicketPrice() private view returns (uint) {
        // Return the current ticket price.
        return currentTicketPrice;
    }

    function getTokenBalance(address tokenAddress) private view returns (uint) {
        IERC20 tokenContract = IERC20(tokenAddress);
        return tokenContract.balanceOf(address(this));
    }

    function getTotalAddressTickets(address _address) private view returns (uint) {
        return map_lotteryNum2Address2NumTickets[lotteryNumber][_address];
    }

    function getTotalTickets() private view returns (uint) {
        return currentTicketNumber;
    }

    /*
        Set Functions
    */

    function setCorruptContract(bool _isCorruptContract) private {
        if(_isCorruptContract) {
            // Do not allow "isCorruptBlock" to keep increasing or multiple events to be issued.
            if(!corruptContractFlag) {
                corruptContractFlag = true;
                corruptContractBlockNumber = block.number;

                emit Corruption(block.number);
            }
        }
        else {
            corruptContractFlag = false;
            corruptContractBlockNumber = 0;

            emit CorruptionReset(block.number);
        }
    }

    function setLocked(bool _isLocked) private {
        lockFlag = _isLocked;
    }

    function setLotteryActiveBlocks(uint newLotteryActiveBlocks) private {
        // Do not set the current active lottery blocks here. When the next lottery starts, the current active lottery blocks will be updated.
        lotteryActiveBlocks = newLotteryActiveBlocks;
    }

    function setOperatorAddress(address newOperatorAddress) private {
        emit OperatorChanged(operatorAddress, newOperatorAddress);
        operatorAddress = newOperatorAddress;
    }
    
    function setOwnerAddress(address _address) private {
        emit OwnerChanged(ownerAddress, _address);
        ownerAddress = _address;
    }

    function setTicketPrice(uint newTicketPrice) private {
        // Do not set the current ticket price here. When the next lottery starts, the current ticket price will be updated.
        ticketPrice = newTicketPrice;
    }

    /*
        Reentrancy Functions
    */

    function lock() private {
        // Call this at the start of each external function that can change state to protect against reentrancy.
        if(isLocked()) {
            punish();
        }
        setLocked(true);
    }

    function unlock() private {
        // Call this at the end of each external function.
        setLocked(false);
    }

    /*
        Utility Functions
    */

    function punish() private pure {
        // This operation will cause a revert but also consume all the gas. This will punish those who are trying to attack the contract.
        assembly("memory-safe") { invalid() }
    }

    function selfDestruct(address _address) private {
        // Destroy this contract and give any native coin balance to the address.
        // The owner is responsible for withdrawing tokens before this contract is destroyed.
        selfdestruct(payable(_address));
    }

    function tokenTransferToAddress(address tokenAddress, address _address, uint value) private {
        // Take extra care to account for tokens that don't revert on failure or that don't return a value.
        // A return value is optional, but if it is present then it must be true.
        // Note that we do not check the token balance ourselves. We defer to the token's contract as to whether the transfer can be done.
        if(tokenAddress.code.length == 0) {
            revert TokenContractError(tokenAddress);
        }

        bytes memory callData = abi.encodeWithSelector(IERC20(tokenAddress).transfer.selector, _address, value);
        (bool success, bytes memory returnData) = tokenAddress.call(callData);

        if(!success || (returnData.length > 0 && !abi.decode(returnData, (bool)))) {
            revert TokenTransferError(tokenAddress, _address, value);
        }
    }

    function transferToAddress(address _address, uint value) private {
        payable(_address).transfer(value);
    }

    /*
    *
    *
        External Functions
    *
    *
    */

    /*
        Action Functions
    */

    /// @notice Players can call this to buy tickets for the current lottery, but only if it is still active and the contract is not corrupt.
    function action_buyTickets() external payable {
        lock();

        requireLotteryActive();
        requireNotCorruptContract();
        requirePlayerAddress(msg.sender);

        buyTickets(msg.sender, msg.value);

        unlock();
    }

    /// @notice The operator can call this before a winning ticket is drawn to cancel the current lottery and refund everyone. The operator gives up their cut and must pay a penalty fee to do this.
    function action_cancelCurrentLottery() external payable {
        lock();

        requireOperatorAddress(msg.sender);
        requireNoWinningTicketDrawn();
        requirePenaltyPayment(msg.value);
        
        cancelCurrentLottery(msg.value);

        unlock();
    }

    /// @notice Anyone can call this before a winning ticket is drawn to cancel the current lottery and refund everyone, but only if the contract is corrupt. There is no penalty fee in this case.
    function action_cancelCurrentLotteryCorrupt() external {
        lock();

        requireNoWinningTicketDrawn();
        requireCorruptContract();
        
        cancelCurrentLottery(0);

        unlock();
    }

    /// @notice Anyone can call this to draw the winning ticket, but only if the current lottery is no longer active.
    function action_drawWinningTicket() external {
        lock();

        requireLotteryInactive();

        drawWinningTicket();

        unlock();
    }

    /// @notice Anyone can call this to end the current lottery, but only if a winning ticket has been drawn.
    function action_endCurrentLottery() external {
        lock();

        requireWinningTicketDrawn();

        endCurrentLottery();

        unlock();
    }

    /*
        Add Functions
    */

    /// @notice Anyone can call this to add funds to the bonus prize pool, but only if the contract is not corrupt.
    function add_bonusPrizePool() external payable {
        lock();

        requireNotCorruptContract();

        addBonusPrizePool(msg.value);

        unlock();
    }

    /// @notice The operator can call this to give funds to the contract.
    function add_contractFunds() external payable {
        lock();

        requireOperatorAddress(msg.sender);

        addContractFunds(msg.value);

        unlock();
    }

    /*
        Withdraw Functions
    */

    /// @notice Anyone can call this to withdraw any claimable balance they have.
    function withdraw_addressClaimableBalance() external {
        lock();

        withdrawAddressClaimableBalance(msg.sender);

        unlock();
    }

    /// @notice Anyone can call this to withdraw a refund.
    /// @param _lotteryNumber The number of a lottery that was canceled.
    function withdraw_addressRefund(uint _lotteryNumber) external {
        lock();

        withdrawAddressRefund(_lotteryNumber, msg.sender);

        unlock();
    }

    /// @notice The owner can call this to withdraw all Chainlink, including the minimum reserve. This can only be used if the contract is ready to be destroyed.
    function withdraw_allChainlinkBalance() external {
        requireOwnerAddress(msg.sender);
        requireSelfDestructReady();

        withdrawAllChainlinkBalance(msg.sender);
    }

    /// @notice The operator can call this to withdraw all contract funds.
    function withdraw_allContractFunds() external {
        lock();

        requireOperatorAddress(msg.sender);

        withdrawAllContractFunds(msg.sender);

        unlock();
    }

    /// @notice The operator can withdraw all of one kind of token. Note that Chainlink is subject to a minimum reserve requirement.
    /// @param tokenAddress The address where the token's contract lives.
    function withdraw_allTokenBalance(address tokenAddress) external {
        lock();

        requireOperatorAddress(msg.sender);

        withdrawAllTokenBalance(tokenAddress, msg.sender);

        unlock();
    }

    /// @notice The owner can call this to withdraw any amount of Chainlink, including the minimum reserve. This can only be used if the contract is ready to be destroyed.
    /// @param value The amount of Chainlink to withdraw.
    function withdraw_chainlinkBalance(uint value) external {
        requireOwnerAddress(msg.sender);
        requireSelfDestructReady();

        withdrawChainlinkBalance(msg.sender, value);
    }

    /// @notice The operator can call this to withdraw an amount of the contract funds.
    /// @param value The amount of contract funds to withdraw.
    function withdraw_contractFunds(uint value) external {
        lock();

        requireOperatorAddress(msg.sender);

        withdrawContractFunds(msg.sender, value);

        unlock();
    }

    /// @notice The operator can trigger a claimable balance withdraw for someone else.
    /// @param _address The address that the operator is triggering the claimable balance withdraw for.
    function withdraw_otherAddressClaimableBalance(address _address) external {
        lock();

        requireOperatorAddress(msg.sender);

        withdrawAddressClaimableBalance(_address);

        unlock();
    }

    /// @notice The operator can trigger a refund withdraw for someone else.
    /// @param _lotteryNumber The number of a lottery that was canceled.
    /// @param _address The address that the operator is triggering the refund withdraw for.
    function withdraw_otherAddressRefund(uint _lotteryNumber, address _address) external {
        lock();

        requireOperatorAddress(msg.sender);

        withdrawAddressRefund(_lotteryNumber, _address);

        unlock();
    }

    /// @notice The operator can withdraw any amount of one kind of token. Note that Chainlink is subject to a minimum reserve requirement.
    /// @param tokenAddress The address where the token's contract lives.
    /// @param value The amount of tokens to withdraw.
    function withdraw_tokenBalance(address tokenAddress, uint value) external {
        lock();

        requireOperatorAddress(msg.sender);

        withdrawTokenBalance(tokenAddress, msg.sender, value);

        unlock();
    }

    /*
        Query Functions
    */

    /// @notice Returns whether the address is playing in the current lottery.
    /// @param _address The address that we are checking whether it is playing or not.
    /// @return Whether the address is playing or not.
    function query_isAddressPlaying(address _address) external view returns (bool) {
        return isAddressPlaying(_address);
    }

    /// @notice Returns whether the contract is currently corrupt.
    /// @return Whether the contract is currently corrupt.
    function query_isCorruptContract() external view returns (bool) {
        return isCorruptContract();
    }

    /// @notice Returns whether we are in the corrupt contract grace period. This value is meaningless unless the contract is corrupt.
    /// @return Whether we are in the corrupt contract grace period.
    function query_isCorruptContractGracePeriod() external view returns (bool) {
        return isCorruptContractGracePeriod();
    }

    /// @notice Returns whether the contract is currently locked.
    /// @return Whether the contract is currently locked.
    function query_isLocked() external view returns (bool) {
        return isLocked();
    }

    /// @notice Returns whether the current lottery is active or not.
    /// @return Whether the current lottery is active or not.
    function query_isLotteryActive() external view returns (bool) {
        return isLotteryActive();
    }

    /// @notice Returns whether the current lottery only has one player.
    /// @return Whether the current lottery only has one player.
    function query_isOnePlayerGame() external view returns (bool) {
        return isOnePlayerGame();
    }

    /// @notice Returns whether the address is the operator address.
    /// @return Whether the address is the operator address.
    function query_isOperatorAddress() external view returns (bool) {
        return isOperatorAddress(msg.sender);
    }

    /// @notice Returns whether the address is the owner address.
    /// @return Whether the address is the owner address.
    function query_isOwnerAddress() external view returns (bool) {
        return isOwnerAddress(msg.sender);
    }

    /// @notice Returns whether the address is an eligible player address.
    /// @return Whether the address is an eligible player address.
    function query_isPlayerAddress() external view returns (bool) {
        return isPlayerAddress(msg.sender);
    }

    /// @notice Returns whether a retry of drawing a winning ticket is permitted.
    /// @return Whether a retry of drawing a winning ticket is permitted.
    function query_isRetryPermitted() external view returns (bool) {
        return isRetryPermitted();
    }

    /// @notice Returns whether the self-destruct is ready.
    /// @return Whether the self-destruct is ready.
    function query_isSelfDestructReady() external view returns (bool) {
        return isSelfDestructReady();
    }

    /// @notice Returns whether a winning ticket has been drawn for the current lottery.
    /// @return Whether a winning ticket has been drawn for the current lottery.
    function query_isWinningTicketDrawn() external view returns (bool) {
        return isWinningTicketDrawn();
    }

    /// @notice Returns whether the current lottery has no players.
    /// @return Whether the current lottery has no players.
    function query_isZeroPlayerGame() external view returns (bool) {
        return isZeroPlayerGame();
    }

    /*
        Get Functions
    */

    /// @notice Returns the contract balance that is accounted for.
    /// @return The contract balance that is accounted for.
    function get_accountedContractBalance() external view returns (uint) {
        return getAccountedContractBalance();
    }

    /// @notice Returns the claimable balance of the address.
    /// @param _address The address that we are checking the claimable balance for.
    /// @return The claimable balance of the address.
    function get_addressClaimableBalance(address _address) external view returns (uint) {
        return getAddressClaimableBalance(_address);
    }

    /// @notice Returns the refund an address is entitled to.
    /// @param _lotteryNumber The number of a lottery that was canceled.
    /// @param _address The address that we are checking the refund for.
    /// @return The claimable balance of the address.
    function get_addressRefund(uint _lotteryNumber, address _address) external view returns (uint) {
        return getAddressRefund(_lotteryNumber, _address);
    }

    /// @notice Returns the predicted number of times that the address will win out of 100 times, truncated to an integer. This is equivalent to the percentage probability of the address winning.
    /// @param _address The address that we are checking the win chance for.
    /// @return The predicted number of times that the address will win out of 100 times.
    function get_addressWinChance(address _address) external view returns (uint) {
        return getAddressWinChance(_address, 100);
    }

    /// @notice Returns the predicted number of times that the address will win out of N times, truncated to an integer. This function can be used to get extra digits in the answer that would normally get truncated.
    /// @param _address The address that we are checking the win chance for.
    /// @param N The total number of times that we want to know how many times the address will win out of.
    /// @return The predicted number of times that the address will win out of N times.
    function get_addressWinChanceOutOf(address _address, uint N) external view returns (uint) {
        return getAddressWinChance(_address, N);
    }

    /// @notice Returns the bonus prize pool. This is the amount of bonus funds that anyone can donate to "sweeten the pot".
    /// @return The bonus prize pool.
    function get_bonusPrizePool() external view returns (uint) {
        return getBonusPrizePool();
    }

    /// @notice Returns the claimable balance pool. This is the total amount of funds that can currently be claimed.
    /// @return The claimable balance pool.
    function get_claimableBalancePool() external view returns (uint) {
        return getClaimableBalancePool();
    }

    /// @notice Returns the entire contract balance. This includes all funds, even those that are unaccounted for.
    /// @return The entire contract balance.
    function get_contractBalance() external view returns (uint) {
        return getContractBalance();
    }

    /// @notice Returns the amount of funds accounted for as contract funds. Note that the actual contract balance may be higher.
    /// @return The amount of contract funds.
    function get_contractFunds() external view returns (uint) {
        return getContractFunds();
    }

    /// @notice Returns the contract balance that is not accounted for.
    /// @return The contract balance that is not accounted for.
    function get_extraContractBalance() external view returns (uint) {
        return getExtraContractBalance();
    }

    /// @notice Returns the total number of active blocks for the current lottery.
    /// @return The total number of active blocks for the current lottery.
    function get_lotteryActiveBlocks() external view returns (uint) {
        return getLotteryActiveBlocks();
    }

    /// @notice Returns the start block number of the current lottery
    /// @return The start block number of the current lottery
    function get_lotteryBlockNumberStart() external view returns (uint) {
        return getLotteryBlockNumberStart();
    }

    /// @notice Returns the current lottery number.
    /// @return The current lottery number.
    function get_lotteryNumber() external view returns (uint) {
        return getLotteryNumber();
    }

    /// @notice Returns the winner's prize of a lottery.
    /// @param _lotteryNumber The number of a lottery that has already finished.
    /// @return The prize that was won for the lottery.
    function get_lotteryWinnerPrize(uint _lotteryNumber) external view returns (uint) {
        return getLotteryWinnerPrize(_lotteryNumber);
    }

    /// @notice Returns the winning address of a lottery.
    /// @param _lotteryNumber The number of a lottery that has already finished.
    /// @return The address that won the lottery.
    function get_lotteryWinningAddress(uint _lotteryNumber) external view returns (address) {
        return getLotteryWinningAddress(_lotteryNumber);
    }

    /// @notice Returns the current operator address.
    /// @return The current operator address.
    function get_operatorAddress() external view returns (address) {
        return getOperatorAddress();
    }

    /// @notice Returns the contract balance that the operator has access to.
    /// @return The contract balance that the operator has access to.
    function get_operatorContractBalance() external view returns (uint) {
        return getOperatorContractBalance();
    }

    /// @notice Returns the current owner address.
    /// @return The current owner address.
    function get_ownerAddress() external view returns (address) {
        return getOwnerAddress();
    }

    /// @notice Returns the current penalty the operator must pay to cancel the current lottery.
    /// @return The current penalty the operator must pay to cancel the current lottery.
    function get_penaltyPayment() external view returns (uint) {
        return getPenaltyPayment();
    }

    /// @notice Returns the player prize pool. This is the amount of funds used to purchase tickets in the current lottery.
    /// @return The player prize pool.
    function get_playerPrizePool() external view returns (uint) {
        return getPlayerPrizePool();
    }

    /// @notice Returns the refund pool. This is the total amount of funds that can currently be refunded from canceled lotteries.
    /// @return The refund pool.
    function get_refundPool() external view returns (uint) {
        return getRefundPool();
    }

    /// @notice Returns the remaining grace period blocks. This value is meaningless unless the contract is corrupt.
    /// @return The remaining grace period blocks.
    function get_remainingCorruptContractGracePeriodBlocks() external view returns (uint) {
        return getRemainingCorruptContractGracePeriodBlocks();
    }

    /// @notice Returns the remaining number of active blocks for the current lottery.
    /// @return The remaining number of active blocks for the current lottery.
    function get_remainingLotteryActiveBlocks() external view returns (uint) {
        return getRemainingLotteryActiveBlocks();
    }

    /// @notice Returns the ticket price of the current lottery.
    /// @return The ticket price of the current lottery.
    function get_ticketPrice() external view returns (uint) {
        return getTicketPrice();
    }

    /// @notice Returns the balance of a token.
    /// @param tokenAddress The address where the token's contract lives.
    /// @return The token balance.
    function get_tokenBalance(address tokenAddress) external view returns (uint) {
        return getTokenBalance(tokenAddress);
    }

    /// @notice Returns the number of tickets an address has in the current lottery.
    /// @param _address The address that we are checking the number of tickets for.
    /// @return The number of tickets the address has in the current lottery.
    function get_totalAddressTickets(address _address) external view returns (uint) {
        return getTotalAddressTickets(_address);
    }

    /// @notice Returns the total number of tickets in the current lottery.
    /// @return The total number of tickets in the current lottery.
    function get_totalTickets() external view returns (uint) {
        return getTotalTickets();
    }

    /*
        Set Functions
    */

    /// @notice The operator can change the total number of active blocks for the lottery. This change will go into effect starting from the next lottery.
    /// @param newLotteryActiveBlocks The new total number of active blocks for the lottery.
    function set_lotteryActiveBlocks(uint newLotteryActiveBlocks) external {
        lock();

        requireOperatorAddress(msg.sender);

        setLotteryActiveBlocks(newLotteryActiveBlocks);

        unlock();
    }

    /// @notice The operator can assign the operator role to a new address.
    /// @param newOperatorAddress The new operator address.
    function set_operatorAddress(address newOperatorAddress) external {
        lock();

        requireOperatorAddress(msg.sender);

        setOperatorAddress(newOperatorAddress);

        unlock();
    }

    /// @notice The owner can transfer ownership to a new address.
    /// @param newOwnerAddress The new owner address.
    function set_ownerAddress(address newOwnerAddress) external {
        lock();

        requireOwnerAddress(msg.sender);

        setOwnerAddress(newOwnerAddress);

        unlock();
    }

    /// @notice The operator can change the ticket price of the lottery. This change will go into effect starting from the next lottery.
    /// @param newTicketPrice The new ticket price of the lottery.
    function set_ticketPrice(uint newTicketPrice) external {
        lock();

        requireOperatorAddress(msg.sender);

        setTicketPrice(newTicketPrice);

        unlock();
    }

    /*
        Diagnostic Functions
    */

    /// @notice The owner can call this to get information about the internal state of the contract.
    function diagnostic_getInternalInfo1() external view returns (bool _lockFlag, bool _corruptContractFlag, uint _corruptContractBlockNumber, uint _lotteryNumber, uint _lotteryBlockNumberStart, uint _lotteryActiveBlocks, uint _currentLotteryActiveBlocks, address _ownerAddress, address _operatorAddress, uint _ticketPrice, uint _currentTicketPrice, uint _contractFunds) {
        requireOwnerAddress(msg.sender);

        return(lockFlag, corruptContractFlag, corruptContractBlockNumber, lotteryNumber, lotteryBlockNumberStart, lotteryActiveBlocks, currentLotteryActiveBlocks, ownerAddress, operatorAddress, ticketPrice, currentTicketPrice, contractFunds);
    }

    /// @notice The owner can call this to get information about the internal state of the contract.
    function diagnostic_getInternalInfo2() external view returns (uint _playerPrizePool, uint _bonusPrizePool, uint _claimableBalancePool, uint _refundPool, uint _currentTicketNumber, uint _chainlinkRetryCounter, bool _chainlinkRequestIdFlag, uint _chainlinkRequestIdBlockNumber, uint _chainlinkRequestIdLotteryNumber, uint _chainlinkRequestId, bool _winningTicketFlag, uint _winningTicket) {
        requireOwnerAddress(msg.sender);

        return(playerPrizePool, bonusPrizePool, claimableBalancePool, refundPool, currentTicketNumber, chainlinkRetryCounter, chainlinkRequestIdFlag, chainlinkRequestIdBlockNumber, chainlinkRequestIdLotteryNumber, chainlinkRequestId, winningTicketFlag, winningTicket);
    }

    /*
        Fail-Safe Functions
    */

    /// @notice The owner can call this to destroy a corrupt contract.
    function failsafe_selfdestruct() external {
        requireOwnerAddress(msg.sender);
        requireSelfDestructReady();

        selfDestruct(msg.sender);
    }

    /// @notice The owner can call this to make themselves the operator.
    function failsafe_takeOperatorRole() external {
        requireOwnerAddress(msg.sender);

        setOperatorAddress(msg.sender);
    }

    /// @notice The owner can call this to uncorrupt the contract. This should only be done if the currupt flag being set was a false positive.
    function failsafe_uncorrupt() external {
        requireOwnerAddress(msg.sender);

        setCorruptContract(false);
    }

    /// @notice The owner can call this to unlock the contract.
    function failsafe_unlock() external {
        requireOwnerAddress(msg.sender);

        setLocked(false);
    }
}