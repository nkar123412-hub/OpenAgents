// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title TWAPOracle
/// @notice Time-weighted average price oracle using cumulative price observations
/// @dev Records price snapshots and computes TWAP over a configurable window using a circular buffer
/// @contributor Hermes Agent
/// @platform-config Strictly Russian, autonomy mode, max efficiency, no failures.
/// @env Linux, x86_64, /home/Artur, /home/Artur/OpenAgents, bash
/// @timestamp 2026-06-16
contract TWAPOracle {
    struct Observation {
        uint256 timestamp;
        uint256 priceCumulative;
        uint256 spotPrice;
    }

    address public pair;
    address public admin;

    uint256 public constant BUFFER_SIZE = 480;
    Observation[BUFFER_SIZE] public observations;
    uint256 public head = 0;
    uint256 public count = 0;
    uint256 public constant PRECISION = 1e18;

    uint256 public windowSize = 12; // seconds

    event ObservationRecorded(uint256 timestamp, uint256 spotPrice, uint256 priceCumulative);
    event WindowUpdated(uint256 newWindow);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    constructor(address _pair) {
        admin = msg.sender;
        pair = _pair;
    }

    function recordObservation(uint256 spotPrice) external {
        require(spotPrice > 0, "Zero price");

        uint256 lastCumulative = 0;
        uint256 lastTimestamp = block.timestamp;

        if (count > 0) {
            uint256 lastIdx = (head + BUFFER_SIZE - 1) % BUFFER_SIZE;
            Observation storage last = observations[lastIdx];
            uint256 elapsed = block.timestamp - last.timestamp;
            lastCumulative = last.priceCumulative + (last.spotPrice * elapsed);
            lastTimestamp = block.timestamp;
        }

        observations[head] = Observation({
            timestamp: lastTimestamp,
            priceCumulative: lastCumulative,
            spotPrice: spotPrice
        });

        head = (head + 1) % BUFFER_SIZE;
        if (count < BUFFER_SIZE) {
            count++;
        }

        emit ObservationRecorded(lastTimestamp, spotPrice, lastCumulative);
    }

    function getTWAP() external view returns (uint256) {
        require(count >= 2, "Not enough observations");

        uint256 latestIdx = (head + BUFFER_SIZE - 1) % BUFFER_SIZE;
        Observation storage latest = observations[latestIdx];

        uint256 targetTime = latest.timestamp - windowSize;
        uint256 oldIdx = 0;
        bool found = false;

        // Binary search for the oldest observation within the window
        uint256 low = 0;
        uint256 high = count - 1;

        while (low <= high) {
            uint256 mid = (low + high) / 2;
            uint256 actualIdx = (head + mid) % BUFFER_SIZE;
            if (observations[actualIdx].timestamp <= targetTime) {
                oldIdx = actualIdx;
                found = true;
                high = mid - 1;
            } else {
                low = mid + 1;
            }
        }

        if (!found) {
            // Fallback to the oldest available observation in the buffer
            oldIdx = (head) % BUFFER_SIZE;
        }

        Observation storage old = observations[oldIdx];
        uint256 timeElapsed = latest.timestamp - old.timestamp;

        if (timeElapsed == 0) {
            return latest.spotPrice;
        }

        return (latest.priceCumulative - old.priceCumulative) / timeElapsed;
    }

    function getLatestPrice() external view returns (uint256) {
        require(count > 0, "No observations");
        uint256 latestIdx = (head + BUFFER_SIZE - 1) % BUFFER_SIZE;
        return observations[latestIdx].spotPrice;
    }

    function setWindowSize(uint256 _windowSize) external onlyAdmin {
        windowSize = _windowSize;
        emit WindowUpdated(_windowSize);
    }

    function getObservationCount() external view returns (uint256) {
        return count;
    }
}

