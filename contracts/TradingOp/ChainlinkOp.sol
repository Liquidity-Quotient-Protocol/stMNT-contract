// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";



//! MI SERVE SOLO SAPERE QUANTI usd CI VOLGIONO PER PRENDERE 1 MNT

contract PriceLogic  {
        address internal priceFeedAddress;


    constructor(address _priceFeedAddress) {
        priceFeedAddress = _priceFeedAddress; 
    }

    function getChainlinkDataFeedLatestAnswer() public view returns (int) {
        AggregatorV3Interface dataFeed = AggregatorV3Interface(
            priceFeedAddress
        );
        (
            ,
            /* uint80 roundID */ int answer /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,
        ) = dataFeed.latestRoundData();
        return answer ; //! PER ORA RITORNIAMO SOLO IL PREZZO SENZA ARROTONDAMENTI , QUESTI LI GESTIAMO DOPO
    }




}
