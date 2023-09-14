// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IBEP20 {
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
}

contract StakingContract {
    address public owner;
    IBEP20 public token;
    uint256 public totalStaked;

    struct Plan {
        uint256 stakingDuration;
        uint256 interestRate;
        uint256 withdrawalPeriod;
    }

    mapping(uint256 => Plan) public plans;

    struct Stake {
        uint256 planId;
        uint256 amount;
        uint256 stakingTimestamp;
        uint256 lastWithdrawnPeriod;
    }

    mapping(address => Stake[]) public stakes;

    event Staked(address indexed user, uint256 planId, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address _tokenAddress) {
        owner = msg.sender;
        token = IBEP20(_tokenAddress);
    }

    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can call this function"
        );
        _;
    }

    function contractBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function tokenBalance(address balanceAddress)
        public
        view
        returns (uint256)
    {
        return token.balanceOf(balanceAddress);
    }

    function addPlan(
        uint256 planId,
        uint256 stakingDuration,
        uint256 interestRate,
        uint256 withdrawalPeriod
    ) external onlyOwner {
        plans[planId] = Plan(stakingDuration, interestRate, withdrawalPeriod);
    }

    function stakeTokens(uint256 planId, uint256 amount)
        external
        returns (bool)
    {
        require(amount > 0, "Amount must be greater than 0");
        require(plans[planId].stakingDuration > 0, "Invalid plan");
        require(token.balanceOf(msg.sender) >= amount, "Insufficient balance");

        bool transferSuccess = token.transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(transferSuccess, "Coin transfer failed");

        Stake memory newStake = Stake(planId, amount, block.timestamp, 0);
        stakes[msg.sender].push(newStake);

        totalStaked += amount;

        emit Staked(msg.sender, planId, amount);

        return transferSuccess;
    }

    function calculateInterest(
        uint256 planId,
        uint256 amount,
        uint256 stakingTime
    ) internal view returns (uint256) {
        Plan memory plan = plans[planId];
        uint256 interest = (amount * plan.interestRate * stakingTime) /
            (plan.stakingDuration * 100);
        return interest;
    }

    function withdrawTokens(uint256 stakeIndex) external {
        require(stakeIndex < stakes[msg.sender].length, "Invalid stake index");

        Stake storage stake = stakes[msg.sender][stakeIndex];
        uint256 currentTime = block.timestamp;
        uint256 stakingTime = currentTime - stake.stakingTimestamp;
    
        uint256 timeDuration = plans[stake.planId].stakingDuration;
        uint256 withdrawalPeriod = plans[stake.planId].withdrawalPeriod;
        uint256 lastWithdrawalTime = stake.stakingTimestamp +
            (stake.lastWithdrawnPeriod * timeDuration);

        require(
            stakingTime >= plans[stake.planId].stakingDuration,
            "Staking duration not reached"
        );
        require(
            currentTime >= lastWithdrawalTime + timeDuration,
            "Too soon to withdraw interest"
        );

        uint256 interest;
        uint256 totalAmount;

        uint256 periodsPassed = (stakingTime - (stake.lastWithdrawnPeriod * timeDuration)) / (timeDuration);

        for (uint256 i = 0; i < periodsPassed; i++) {

            interest = calculateInterest(
                stake.planId,
                stake.amount,
                timeDuration
            ); 

            totalAmount += interest;
        }

        stake.lastWithdrawnPeriod += periodsPassed ;
 
        if (stake.lastWithdrawnPeriod >= withdrawalPeriod) {

            interest = calculateInterest(
                stake.planId,
                stake.amount,
                timeDuration
            );
            totalAmount = stake.amount + interest;
            totalStaked -= stake.amount;
            removeStake(msg.sender, stakeIndex);
        }

        token.transfer(msg.sender, totalAmount);

        emit Withdrawn(msg.sender, totalAmount);
    }


    function removeStake(address user, uint256 index) internal {
        if (index >= stakes[user].length) return;

        for (uint256 i = index; i < stakes[user].length - 1; i++) {
            stakes[user][i] = stakes[user][i + 1];
        }

        stakes[user].pop();
    }

    function withdrawExcessTokens(address _tokenAddress) external onlyOwner {
        IBEP20 excessToken = IBEP20(_tokenAddress);
        uint256 balance = excessToken.balanceOf(address(this));
        excessToken.transfer(msg.sender, balance);
    }

    function removePlan(uint256 planId) external onlyOwner {
        require(plans[planId].stakingDuration > 0, "Plan does not exist");

        for (uint256 i = 0; i < stakes[msg.sender].length; i++) {
            if (stakes[msg.sender][i].planId == planId) {
                totalStaked -= stakes[msg.sender][i].amount;
                removeStake(msg.sender, i);
                i--; 
            }
        }

        delete plans[planId]; 
    }
}
