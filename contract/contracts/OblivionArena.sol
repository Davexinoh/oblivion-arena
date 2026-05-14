// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IVOIDToken {
    function mintStarterPack(address _to) external;
    function burn(address _from, uint256 _amount) external;
    function rewardWinner(address _to, uint256 _amount) external;
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract OblivionArena {
    uint256 public constant TRAIN_COST = 10 * 10 ** 18;
    uint256 public constant BOUNTY_MIN = 50 * 10 ** 18;
    uint256 public constant WIN_REWARD = 25 * 10 ** 18;
    uint8 public constant FIGHT_ROUNDS = 5;
    uint8 public constant SOUL_THRESHOLD = 8;
    uint256 public constant DECAY_INTERVAL = 7 days;

    struct Fighter {
        uint256 id;
        address owner;
        string name;
        string username;
        uint8 character;
        uint8 brutality;
        uint8 iron;
        uint8 reflex;
        uint8 soul;
        uint256 wins;
        uint256 losses;
        uint256 totalDamageDealt;
        uint256 lastFightTime;
        uint256 lastTrainTime;
        bool exists;
    }

    struct Bounty {
        uint256 bountyId;
        uint256 targetFighterId;
        address poster;
        uint256 amount;
        bool claimed;
        bool exists;
    }

    struct BattleRecord {
        uint256 battleId;
        uint256 challengerId;
        uint256 opponentId;
        uint256 winnerId;
        uint256 challengerDamage;
        uint256 opponentDamage;
        uint256 timestamp;
    }

    uint256 public fighterCount;
    uint256 public bountyCount;
    uint256 public battleCount;

    IVOIDToken public voidToken;
    address public owner;

    mapping(uint256 => Fighter) public fighters;
    mapping(address => uint256[]) public ownerFighters;
    mapping(address => bool) public hasFirstFighter;
    mapping(uint256 => Bounty) public bounties;
    mapping(uint256 => uint256[]) public fighterBounties;
    mapping(uint256 => BattleRecord) public battles;
    mapping(uint256 => uint256[]) public fighterBattles;

    event FighterMinted(uint256 indexed fighterId, address indexed owner, string name, uint8 character);
    event StatTrained(uint256 indexed fighterId, uint8 stat, uint8 newValue);
    event FightResolved(uint256 indexed battleId, uint256 challengerId, uint256 opponentId, uint256 winnerId, uint256 challengerDamage, uint256 opponentDamage);
    event BountyPosted(uint256 indexed bountyId, uint256 indexed targetFighterId, address poster, uint256 amount);
    event BountyClaimed(uint256 indexed bountyId, uint256 indexed claimerFighterId, address claimer, uint256 amount);
    event StatDecayed(uint256 indexed fighterId, uint8 stat, uint8 newValue);

    modifier onlyOwner() { require(msg.sender == owner, "Not owner"); _; }
    modifier fighterExists(uint256 id) { require(fighters[id].exists, "Fighter not found"); _; }
    modifier onlyFighterOwner(uint256 id) { require(fighters[id].owner == msg.sender, "Not fighter owner"); _; }

    constructor(address _voidToken) {
        owner = msg.sender;
        voidToken = IVOIDToken(_voidToken);
    }

    function getBaseStats(uint8 character) internal pure returns (uint8, uint8, uint8, uint8) {
        if (character == 0) return (9, 3, 6, 7);
        if (character == 1) return (6, 2, 10, 5);
        if (character == 2) return (5, 10, 2, 7);
        if (character == 3) return (4, 4, 7, 10);
        if (character == 4) return (7, 6, 6, 6);
        return (3, 5, 8, 8);
    }

    function mintFighter(string calldata _name, string calldata _username, uint8 _character) external {
        require(_character <= 5, "Invalid character");
        require(bytes(_name).length > 0 && bytes(_name).length <= 32, "Invalid name");
        require(bytes(_username).length > 0 && bytes(_username).length <= 32, "Invalid username");

        fighterCount++;
        (uint8 b, uint8 i, uint8 r, uint8 s) = getBaseStats(_character);

        fighters[fighterCount] = Fighter({
            id: fighterCount, owner: msg.sender, name: _name, username: _username,
            character: _character, brutality: b, iron: i, reflex: r, soul: s,
            wins: 0, losses: 0, totalDamageDealt: 0,
            lastFightTime: block.timestamp, lastTrainTime: block.timestamp, exists: true
        });

        ownerFighters[msg.sender].push(fighterCount);

        if (!hasFirstFighter[msg.sender]) {
            hasFirstFighter[msg.sender] = true;
            voidToken.mintStarterPack(msg.sender);
        }

        emit FighterMinted(fighterCount, msg.sender, _name, _character);
    }

    function trainStat(uint256 _fighterId, uint8 _stat) external fighterExists(_fighterId) onlyFighterOwner(_fighterId) {
        require(_stat <= 3, "Invalid stat");
        require(voidToken.balanceOf(msg.sender) >= TRAIN_COST, "Not enough VOID");

        voidToken.burn(msg.sender, TRAIN_COST);
        Fighter storage f = fighters[_fighterId];
        uint8 newValue;

        if (_stat == 0) { f.brutality += 1; newValue = f.brutality; }
        else if (_stat == 1) { f.iron += 1; newValue = f.iron; }
        else if (_stat == 2) { f.reflex += 1; newValue = f.reflex; }
        else { f.soul += 1; newValue = f.soul; }

        f.lastTrainTime = block.timestamp;
        emit StatTrained(_fighterId, _stat, newValue);
    }

    function resolveFight(uint256 _challengerId, uint256 _opponentId) external fighterExists(_challengerId) fighterExists(_opponentId) onlyFighterOwner(_challengerId) {
        require(_challengerId != _opponentId, "Cannot fight yourself");

        Fighter storage c = fighters[_challengerId];
        Fighter storage o = fighters[_opponentId];
        uint256 cTotal = 0; uint256 oTotal = 0;

        for (uint8 i = 0; i < FIGHT_ROUNDS; i++) {
            uint256 cRaw = c.brutality > o.iron ? c.brutality - o.iron : 1;
            uint256 cDmg = c.reflex > o.reflex ? cRaw + cRaw / 5 : cRaw;
            cTotal += cDmg + (c.soul >= SOUL_THRESHOLD ? 2 : 0);

            uint256 oRaw = o.brutality > c.iron ? o.brutality - c.iron : 1;
            uint256 oDmg = o.reflex > c.reflex ? oRaw + oRaw / 5 : oRaw;
            oTotal += oDmg + (o.soul >= SOUL_THRESHOLD ? 2 : 0);
        }

        bool cWins = cTotal > oTotal || (cTotal == oTotal && c.soul >= o.soul);
        uint256 winnerId = cWins ? _challengerId : _opponentId;
        address winnerOwner = cWins ? c.owner : o.owner;

        c.totalDamageDealt += cTotal; o.totalDamageDealt += oTotal;
        c.lastFightTime = block.timestamp; o.lastFightTime = block.timestamp;

        if (cWins) { c.wins++; o.losses++; } else { o.wins++; c.losses++; }

        voidToken.rewardWinner(winnerOwner, WIN_REWARD);

        battleCount++;
        battles[battleCount] = BattleRecord(battleCount, _challengerId, _opponentId, winnerId, cTotal, oTotal, block.timestamp);
        fighterBattles[_challengerId].push(battleCount);
        fighterBattles[_opponentId].push(battleCount);

        emit FightResolved(battleCount, _challengerId, _opponentId, winnerId, cTotal, oTotal);
    }

    function postBounty(uint256 _targetFighterId) external fighterExists(_targetFighterId) {
        require(fighters[_targetFighterId].owner != msg.sender, "Cannot bounty own fighter");
        require(voidToken.balanceOf(msg.sender) >= BOUNTY_MIN, "Not enough VOID");

        voidToken.transferFrom(msg.sender, address(this), BOUNTY_MIN);
        bountyCount++;
        bounties[bountyCount] = Bounty(bountyCount, _targetFighterId, msg.sender, BOUNTY_MIN, false, true);
        fighterBounties[_targetFighterId].push(bountyCount);

        emit BountyPosted(bountyCount, _targetFighterId, msg.sender, BOUNTY_MIN);
    }

    function claimBounty(uint256 _bountyId, uint256 _claimerFighterId) external fighterExists(_claimerFighterId) onlyFighterOwner(_claimerFighterId) {
        Bounty storage bounty = bounties[_bountyId];
        require(bounty.exists && !bounty.claimed, "Invalid bounty");

        bool verified = false;
        uint256[] memory cb = fighterBattles[_claimerFighterId];
        for (uint256 i = 0; i < cb.length; i++) {
            BattleRecord memory b = battles[cb[i]];
            if (b.winnerId == _claimerFighterId && (b.challengerId == bounty.targetFighterId || b.opponentId == bounty.targetFighterId)) {
                verified = true; break;
            }
        }

        require(verified, "Have not beaten target fighter");
        bounty.claimed = true;
        voidToken.transferFrom(address(this), msg.sender, bounty.amount);

        emit BountyClaimed(_bountyId, _claimerFighterId, msg.sender, bounty.amount);
    }

    function decayFighter(uint256 _fighterId) external onlyOwner fighterExists(_fighterId) {
        Fighter storage f = fighters[_fighterId];
        require(block.timestamp >= f.lastFightTime + DECAY_INTERVAL, "Not eligible");

        uint8 minVal = 255; uint8 minStat = 0;
        if (f.brutality > 1 && f.brutality < minVal) { minVal = f.brutality; minStat = 0; }
        if (f.iron > 1 && f.iron < minVal) { minVal = f.iron; minStat = 1; }
        if (f.reflex > 1 && f.reflex < minVal) { minVal = f.reflex; minStat = 2; }
        if (f.soul > 1 && f.soul < minVal) { minStat = 3; }

        uint8 newValue;
        if (minStat == 0) { f.brutality -= 1; newValue = f.brutality; }
        else if (minStat == 1) { f.iron -= 1; newValue = f.iron; }
        else if (minStat == 2) { f.reflex -= 1; newValue = f.reflex; }
        else { f.soul -= 1; newValue = f.soul; }

        f.lastFightTime = block.timestamp;
        emit StatDecayed(_fighterId, minStat, newValue);
    }

    function getFighter(uint256 _fighterId) external view fighterExists(_fighterId) returns (Fighter memory) { return fighters[_fighterId]; }
    function getOwnerFighters(address _owner) external view returns (uint256[] memory) { return ownerFighters[_owner]; }
    function getFighterBattles(uint256 _fighterId) external view returns (uint256[] memory) { return fighterBattles[_fighterId]; }
    function getFighterBounties(uint256 _fighterId) external view returns (uint256[] memory) { return fighterBounties[_fighterId]; }
    function getBattle(uint256 _battleId) external view returns (BattleRecord memory) { return battles[_battleId]; }
    function getBounty(uint256 _bountyId) external view returns (Bounty memory) { return bounties[_bountyId]; }

    function getRecentBattles(uint256 count) external view returns (BattleRecord[] memory) {
        uint256 total = battleCount;
        uint256 resultCount = count > total ? total : count;
        BattleRecord[] memory result = new BattleRecord[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) { result[i] = battles[total - i]; }
        return result;
    }
}
