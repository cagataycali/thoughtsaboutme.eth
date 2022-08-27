// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hstp/HSTP.sol";

struct Thought {
    address to; // Who is the target address?
    string message; // What is the message? -> IPFS or text
    // TAM has one anonymous address.
    // That address control your NFT.
    // IF YOU WANT TO CREATE ANONYMOUS NFT.
    uint256 isAnonymous; // IS ANONYMOUS?
    address origin; // WHO WROTE THE THOUGHT, if it's anonymous, origin is anonymous.
    // Frontend will send origin as empty string, thought will be created by backend.
    // But you can control the NFT, because the ANONYMOUS know you, it's a trust based relationship.
    uint256 createdAt;
    uint256 price; // The sacrifice of the thought for the executor.
}

struct Query {
    address addr;
    uint256 operation;
    // 0 -> get thought count
    // 1 -> get latest message
}

/// @custom:security-contact cagataycali@icloud.com
contract thoughtsaboutme is
    HSTP("thoughtsaboutme"),
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    Ownable
{
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    uint256 public price = 0.01 ether; // MATIC
    // IPFS ADDRESS ONLY
    string public baseURL = "ipfs://";
    string public baseContractURL =
        "https://thoughtsaboutme.xyz/contract-metadata/";

    constructor() ERC721("thoughtsaboutme", "thoughtsaboutme") {}

    mapping(address => uint256) thoughtCount;
    mapping(address => uint256[]) thoughtTokenIndex;
    // {address: [<_tokenIdCounter>: Thought]}
    mapping(address => mapping(uint256 => Thought)) public thoughts;
    // 1. NFT -> 0x171
    // 2.NFT -> 0x123
    mapping(uint256 => address) public recievers;
    mapping(address => uint256) public worth; // Worth of identity.

    // Task pool
    // <tokenId> -> <taskId>
    // When one person creates a task, it will be added to the task pool.
    // If the thought marked as private, joins to the que.
    // Public thoughts is free, public thought generators make money when any tought created over their account.
    // Private toughts pays the fee.
    // Flow:
    // 1. One person create a private tought.
    // 2. Person pays the price of the tought. [The person decide the price >= 0.01 ether]
    // 3. The person's tought joins the que.
    // 4. The person's tought is going to be processed by another person.
    // --- wait in the que ---
    // 1. Another person create a public tought.
    // 2. The person's tought is processed and minted with .
    Thought[] public taskPool;

    function contractURI() public view returns (string memory) {
        return baseContractURL;
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (Thought[] memory)
    {
        // Loop thoughtTokenIndex and get the tokenIds.
        // Then loop thought and get the thoughts.
        // Then return the thoughts.
        uint256[] memory tokenIds = thoughtTokenIndex[_owner];
        Thought[] memory _thoughts = new Thought[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _thoughts[i] = thoughts[_owner][tokenIds[i]];
        }
        return _thoughts;
    }

    // Owner of contract can decide the minting price,
    function setPrice(uint256 _newPrice) public onlyOwner {
        price = _newPrice;
    }

    // Owner of contract can decide the base URL,
    function setBaseURL(string memory _baseURL) public onlyOwner {
        baseURL = _baseURL;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURL;
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        delete thoughts[recievers[tokenId]][tokenId];
        super._burn(tokenId);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return string(abi.encodePacked(baseURL, Strings.toString(tokenId)));
    }

    // ERC721Enumerable overrides,
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, Router, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // it is very important to have a paper trail in the event of a dispute.
    // If the trail is anonymous, you'll wisper your toughts into a task que.
    // The person who is the executor of the task will be able to read the toughts and make it real.
    // If the trail is public, you'll post your toughts to the public.
    function paperTrail(Thought memory thought)
        public
        payable
        returns (Response memory res)
    {
        // The backend function will call mint for anonymous mints.
        _tokenIdCounter.increment();
        uint256 tokenId = _tokenIdCounter.current();
        // If the message is anonymous, the backend is going to pay the price for you.
        // Anonymous is the owner of thoughts.
        if (thought.isAnonymous == 1) {
            require(msg.value >= price && msg.value == thought.price, "sacrifice your time");
            // add this to the task queue.
            taskPool.push(thought);
        } else {
            // Mint another tought for someone else to anonymous, free.
            // Make money with it - even you do not know who is the target address.
            // You're a messenger only.
            // Select the first tougth in the task queue.
            // If the task is not empty, the first thought is the one to be processed.
            if (taskPool.length > 0) {
                Thought memory task = taskPool[0];
                // Process the thought.
                // The anonymous will be the owner of the thought.
                // But the minter is another person :)
                _safeMint(owner(), tokenId);
                // Remove the task from the queue.
                delete taskPool[0];
                worth[task.to] += task.price;
                // Send the price to the miner!
                // Transfer balance to the msg.sender;
                (bool sent,) = msg.sender.call{value: task.price}("");
                require(sent, "Failed to send Ether");
            }
            // Mint your tought - free.
            _safeMint(msg.sender, tokenId);
        }
        thought.createdAt = block.timestamp;

        thoughts[thought.to][tokenId] = thought;
        thoughtCount[thought.to] = thoughtCount[thought.to] + 1;
        // Add the tokenId to tokenIndex
        thoughtTokenIndex[thought.to].push(tokenId);
        // Save the token id for receiver.
        recievers[tokenId] = thought.to;
        res.body = Strings.toString(thought.createdAt);
        return res;
    }

    // Override for HSTP.
    function query(bytes memory payload)
        public
        view
        virtual
        override
        returns (Response memory res)
    {
        Query memory q = abi.decode(payload, (Query));
        if (q.operation == 1) {
            res.body = thoughts[q.addr][thoughtCount[q.addr]].message;
        } else {
            res.body = Strings.toString(thoughtCount[q.addr]);
        }
        return res;
    }

    function mutation(bytes memory payload)
        public
        payable
        virtual
        override
        returns (Response memory)
    {
        Thought memory t = abi.decode(payload, (Thought));
        return this.paperTrail(t);
    }
}
