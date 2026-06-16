// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/ randomness/VRFConsumerBaseV2Plus.sol";

/// @title RandomLottery
/// @notice On-chain lottery using Chainlink VRF for secure randomness
/// @dev Players buy tickets, and a random winner is selected using VRF
/// @contributor Hermes Agent
/// @platform-config Strictly Russian, autonomy mode, max efficiency, no failures.
/// @env Linux, x86_64, /home/Artur, /home/Artur/OpenAgents, bash
/// @timestamp 2026-06-16
contract RandomLottery is VRFConsumerBaseV2Plus {
    address public owner;
    uint256 public ticketPrice;
    uint256 public roundEnd;
    uint256 public currentRound;
    uint256 public lastDrawTimestamp;
    uint256 public constant DRAW_COOLDOWN = 1 hours;

    address[] public players;
    mapping(uint256 => address) public roundWinners;
    mapping(address => bool) public unclaimedPrizes;
    mapping(uint256 => uint256) public roundPrizes;

    event TicketPurchased(address indexed player, uint256 round);
    event RoundStarted(uint256 indexed round, uint256 endTime);
    event WinnerSelected(address indexed winner, uint256 prize, uint256 round);
    event RequestSent(uint256 requestId, uint256 round);
    event PrizeClaimed(address indexed winner, uint256 prize, uint256 round);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        uint256 _ticketPrice,
        address vrfCoordinator
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        owner = msg.sender;
        ticketPrice = _ticketPrice;
    }

    function startRound(uint256 duration) external onlyOwner {
        require(roundEnd == 0 || block.timestamp > roundEnd, "Round active");
        delete players;
        currentRound++;
        roundEnd = block.timestamp + duration;
        emit RoundStarted(currentRound, roundEnd);
    }

    function buyTicket() external payable {
        require(block.timestamp < roundEnd, "Round ended");
        require(msg.value == ticketPrice, "Wrong ticket price");
        players.push(msg.sender);
        emit TicketPurchased(msg.sender, currentRound);
    }

    function requestWinner() external onlyOwner {
        require(block.timestamp >= roundEnd, "Round not ended");
        require(players.length >= 3, "Min 3 participants required");
        require(block.timestamp >= lastDrawTimestamp + DRAW_COOLDOWN, "Draw cooldown active");

        uint256 requestId = this.requestRandomWords(
            uint256(1), // 1 request
            3,           // 3 confirmations
            100000      // callback gas limit
        );
        
        emit RequestSent(requestId, currentRound);
    }

    function fulfillRandomWords(
        uint256 requestId,
        uint256[] memory randomWords
    ) internal override {
        uint256 randomIndex = randomWords[0] % players.length;
        address winner = players[randomIndex];
        
        uint256 prize = address(this).balance;
        roundWinners[currentRound] = winner;
        roundPrizes[currentRound] = prize;
        unclaimedPrizes[winner] = true;

        lastDrawTimestamp = block.timestamp;
        roundEnd = 0;

        emit WinnerSelected(winner, prize, currentRound);
    }

    function claimPrize(uint256 round) external {
        require(roundWinners[round] == msg.sender, "Not the winner of this round");
        require(unclaimedPrizes[msg.sender], "Prize already claimed");

        uint256 prize = roundPrizes[round];
        unclaimedPrizes[msg.sender] = false;
        
        (bool sent, ) = msg.sender.call{value: prize}("");
        require(sent, "Transfer failed");

        emit PrizeClaimed(msg.sender, prize, round);
    }

    function getPlayers() external view returns (address[] memory) {
        return players;
    }

    function getPoolSize() external view returns (uint256) {
        return address(this).balance;
    }
}

