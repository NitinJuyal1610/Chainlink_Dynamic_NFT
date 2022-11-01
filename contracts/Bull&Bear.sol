// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@chainlink/contracts/src/v0.8/AutomationCompatible.sol";

// Dev imports. This only works on a local dev network
// and will not work on any test or main livenets.
import "hardhat/console.sol";

contract BullBear is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable , AutomationCompatibleInterface, VRFConsumerBaseV2{
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;
    uint256 public interval;
    uint256 public lastTimeStamp;
    AggregatorV3Interface public priceFeed;
    VRFCoordinatorV2Interface COORDINATOR;
    uint64 s_subscriptionId;
    //goerli key hash
    bytes32 keyHash=0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
    int256 public currentPrice;

    uint32 callbackGasLimit = 500000;
    uint16 requestConfirmations = 3;
    uint32 numWords = 1;


    // IPFS URIs for the dynamic nft graphics/metadata.
    // NOTE: These connect to my IPFS Companion node.
    // You should upload the contents of the /ipfs folder to your own node for development.
    string[] bullUrisIpfs = [
        "https://ipfs.io/ipfs/QmRXyfi3oNZCubDxiVFre3kLZ8XeGt6pQsnAQRZ7akhSNs?filename=gamer_bull.json",
        "https://ipfs.io/ipfs/QmRJVFeMrtYS2CUVUM2cHJpBV5aX2xurpnsfZxLTTQbiD3?filename=party_bull.json",
        "https://ipfs.io/ipfs/QmdcURmN1kEEtKgnbkVJJ8hrmsSWHpZvLkRgsKKoiWvW9g?filename=simple_bull.json"
    ];
    string[] bearUrisIpfs = [
        "https://ipfs.io/ipfs/Qmdx9Hx7FCDZGExyjLR6vYcnutUR8KhBZBnZfAPHiUommN?filename=beanie_bear.json",
        "https://ipfs.io/ipfs/QmTVLyTSuiKGUEmb88BgXG3qNC8YgpHZiFbjHrXKH3QHEu?filename=coolio_bear.json",
        "https://ipfs.io/ipfs/QmbKhBXVWmwrYsTPFYfroR2N7NAekAMxHUVg2CWks7i9qj?filename=simple_bear.json"
    ];

    event TokenUpdated(string marketTrend);
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    struct RequestStatus {
        bool fulfilled; // whether the request has been successfully fulfilled
        bool exists; // whether a requestId exists
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus) public s_requests;
    

    //past req
    uint256[] public requestIds;
    uint256 public lastRequestId;
    constructor(uint updateInterval,address _priceFeed,uint64 subscriptionId) ERC721("Bull&Bear", "BBTK") VRFConsumerBaseV2(0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed){ 
        //set the keeper update interval
        interval=updateInterval;
        lastTimeStamp=block.timestamp;
        priceFeed = AggregatorV3Interface(_priceFeed);
        currentPrice=getLatestPrice();
        COORDINATOR = VRFCoordinatorV2Interface(0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed);
        s_subscriptionId = subscriptionId;
    }

    function safeMint(address to) public {
        // Current counter value will be the minted token's token ID.
        uint256 tokenId = _tokenIdCounter.current();

        // Increment it so next time it's correct when we call .current()
        _tokenIdCounter.increment();

        // Mint the token
        _safeMint(to, tokenId);
 


        // Default to a bull NFT
        string memory defaultUri = bullUrisIpfs[0];
        _setTokenURI(tokenId, defaultUri);

      
            
    } 

    //for debugging
    function setInterval(uint256 newInterval)public onlyOwner{
        interval=newInterval;
    }

    function setPriceFeed(address newFeed) public onlyOwner{
        priceFeed = AggregatorV3Interface(newFeed);
    }



    function checkUpkeep(bytes calldata /*checkData*/ )external view override returns (bool upkeepNeeded,bytes memory /*performData*/){
        upkeepNeeded=(block.timestamp-lastTimeStamp)>interval; 
    }

    function performUpkeep(bytes calldata /*perform Data */)external override {
        if((block.timestamp-lastTimeStamp)>interval ){
            lastTimeStamp=block.timestamp;
             requestRandomness(); 
        }
    }

    
    // function updateAllTokenUris(string memory trend)internal{
    //     uint index=0;
    //     if(compareStrings("bear",trend)){
    //         for(uint i=0;i<_tokenIdCounter.current();i++){
    //              index=(rand%bearUrisIpfs.length);
    //             _setTokenURI(i,bearUrisIpfs[index]);
    //         }
    //     }else{
    //         for(uint i=0;i<_tokenIdCounter.current();i++){
    //              index=(rand%bullUrisIpfs.length);
    //             _setTokenURI(i,bullUrisIpfs[index]);
    //         }
    //     }
        
    //     emit TokenUpdated(trend);
    // }


    function getLatestPrice()public view returns(int256){
       (,int price,,,)= priceFeed.latestRoundData();
       return price;
    }

    function compareStrings(string memory a,string memory b)internal pure returns (bool){
        return(keccak256(abi.encodePacked(a))==keccak256(abi.encodePacked(b)));
    }

    function requestRandomness() internal{
        uint requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        lastRequestId=requestId;
        s_requests[requestId] = RequestStatus({randomWords: new uint256[](0), exists: true, fulfilled: false});
        requestIds.push(requestId);
        emit RequestSent(requestId, numWords);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        require(s_requests[_requestId].exists, "request not found");
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        uint rand=_randomWords[0];
        uint index=0;
        int latestPrice=getLatestPrice();
        if(latestPrice==currentPrice)return;
        else if(latestPrice<currentPrice){
            for(uint i=0;i<_tokenIdCounter.current();i++){
                 index=(rand%bearUrisIpfs.length);
                _setTokenURI(i,bearUrisIpfs[index]);
            }
        emit TokenUpdated("bear");
        }
        else if(latestPrice>currentPrice){
               for(uint i=0;i<_tokenIdCounter.current();i++){
                 index=(rand%bullUrisIpfs.length);
                _setTokenURI(i,bullUrisIpfs[index]);
            }
             emit TokenUpdated("bull");
        }
        emit RequestFulfilled(_requestId, _randomWords);
    }

    function getRequestStatus(uint256 _requestId) public view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }


    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

     function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }


    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
