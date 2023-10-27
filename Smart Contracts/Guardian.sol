// SPDX-License-Identifier: GPL-3.0



pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./GRewards.sol";
import "./gspay.sol";

contract Guardian is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount; // Staked token amount by the user
        uint256 pendingReward; // Pending rewards to be claimed by the user
    }

    struct PoolInfo {
        IERC20 lpToken; // Token used in the staking pool
        uint256 allocPoint; // Allocation points for reward distribution
        uint256 lastRewardBlock;  // Last block for reward distribution
        uint256 rewardTokenPerShare; // Reward per share per staked token
    }

    GRewards public gs;  // Address of reward distribution contract
    Gspay public gspay;   // Address of token transfer contract
    address public dev; // Developer/administrator address
    uint256 public gsPerBlock;  // GS tokens rewarded per block

    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // User-specific staking information

    PoolInfo[] public poolInfo; // Information about staking pools
    uint256 public totalAllocation = 0; // Total allocation points among pools
    uint256 public startBlock;  // Start block for rewards
    uint256 public BONUS_MULTIPLIER; // Multiplier for reward calculations

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);  // User deposits into a staking pool
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount); // User withdraws from a staking pool
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);  // Emergency withdrawal

    // Constructor to initialize the Guardian contract with essential parameters.
    constructor(
        GRewards _gs, // Reward distribution contract address
        Gspay _gspay,    // Token transfer contract address
        address _dev,  // Developer/administrator address
        uint256 _gsPerBlock,        // Reward tokens per block
        uint256 _startBlock,  // Start block for rewards
        uint256 _multiplier  // Reward multiplier
    ) Ownable(msg.sender) public  {
        gspay = _gspay;
        gs = _gs;
        dev = _dev;
        gsPerBlock = _gsPerBlock;
        startBlock = _startBlock;
        BONUS_MULTIPLIER = _multiplier;

        poolInfo.push(
            PoolInfo({
                lpToken: _gs,
                allocPoint: 1000,
                lastRewardBlock: _startBlock,
                rewardTokenPerShare: 0
            })
        );
        totalAllocation = 1000;
    }

   // Validate pool ID.
    modifier validatePool(uint256 _pid) {    
        require(_pid < poolInfo.length, "Pool Id Invalid");
        _; 
    }
   
   // Retrieve staking pool info by pool ID.
    function getPoolInfo(uint256 _pid)
        public
        view
        returns (
            address lpToken, // Staking token
            uint256 allocPoint,  // Allocation points
            uint256 lastRewardBlock,   // Last reward block
            uint256 rewardTokenPerShare // Reward per share.
        )
    {
         // Get info from the specified staking pool.
        return (
            address(poolInfo[_pid].lpToken),
            poolInfo[_pid].allocPoint,
            poolInfo[_pid].lastRewardBlock,
            poolInfo[_pid].rewardTokenPerShare
        );
    }
    // Get the number of staking pools.
    function poolLength() external view returns (uint256) {
        return poolInfo.length; 
    }

    // Calculate reward multiplier for a block range.
    function getMultiplier(uint256 _from, uint256 _to)
        public
        view
        returns (uint256)
    {
        return _to.sub(_from).mul(BONUS_MULTIPLIER); // Return reward multiplier.
    }


    // Set reward multiplier for pools (owner-only).
    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber; 
    }

     // Check for duplicate staking pools with the same token.
    function checkPoolDuplicate(IERC20 _lpToken) public view {
        uint256 length = poolInfo.length;
        for (uint256 _pid = 0; _pid < length; _pid++) {
            require(poolInfo[_pid].lpToken != _lpToken, "Pool Already Exists");
        }
    }
    // Internal function for updating the staking pool allocation points.
    function updateStakingPool() internal {
        uint256 length = poolInfo.length; // Get the total number of staking pools.
        uint256 points = 0; // Initialize a variable to accumulate allocation points.
      
       // Iterate through all staking pools (excluding the first one).
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint); // Accumulate allocation points.
        }
        if (points != 0) { // Check if there are allocation points to distribute.
            points = points.div(3); // Divide the accumulated points by 3.
            // Adjust the total allocation by subtracting the first pool's allocation and adding the new points.
            totalAllocation = totalAllocation.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;  // Set the allocation points of the first pool to the calculated value.
        }
    }
    // Function for the contract owner to add a new staking pool.
    function add(uint256 _allocPoint, IERC20 _lpToken) public onlyOwner {
        // Check if a staking pool with the provided token already exists (prevents duplicates).
        checkPoolDuplicate(_lpToken);
         // Determine the last reward block based on the current block number or the contract's start block.
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        // Increase the total allocation points with the new pool's allocation points.
        totalAllocation = totalAllocation.add(_allocPoint);

        // Create and append a new staking pool to the poolInfo array.
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken, // The staking token for the new pool.
                allocPoint: _allocPoint, // Allocation points for the new pool
                lastRewardBlock: lastRewardBlock, // The last block number for reward distribution.
                rewardTokenPerShare: 0   // Initialize the reward distribution per share.
            })
        );
        updateStakingPool();
    }

    function updatePool(uint256 _pid) public validatePool(_pid) {
        PoolInfo storage pool = poolInfo[_pid];  // Get information about the specified staking pool.

        if (block.number < pool.lastRewardBlock) {
            return;  // If the current block is earlier than the last reward block, no update is needed.
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));  // Get the balance of staked tokens in the pool
        if (lpSupply == 0){
            pool.lastRewardBlock = block.number;
            return;  // If the staked token supply is zero, update the last reward block and exit.
        }
        // Calculate the total reward tokens for the pool based on allocation points.
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number); 


        // Calculate the total reward tokens for the pool based on allocation points.
        uint256 tokenReward = multiplier.mul(gsPerBlock).mul(pool.allocPoint).div(totalAllocation);
        gs.mint(dev, tokenReward.div(10)); // Mint and allocate a portion of the tokens to the developer/administrator.
        gs.mint(address(gspay), tokenReward);  // Mint and allocate the remaining tokens to the Gspay contract for distribution.
        pool.rewardTokenPerShare = pool.rewardTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply)); // Update the reward per share earned by each staked token.
        pool.lastRewardBlock = block.number; // Update the last reward block for the pool.
    }

       function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            // Subtract the previous allocation points and add the new allocation points to the total allocation.
            totalAllocation = totalAllocation.sub(prevAllocPoint).add(_allocPoint);
             // Update the allocation points of the staking pool.
            updateStakingPool();
        }
    }

   function massUpdatePools() public {
        uint256 length = poolInfo.length; // Get the total number of staking pools in the contract.
            // Iterate through all staking pools.
        for (uint256 pid = 0; pid < length; ++pid) {
            // Call the 'updatePool' function for each staking pool to update their reward information.
            updatePool(pid);
        }
    }

      function pendingReward(uint256 _pid, address _user) external view returns (uint256) {
         // Get information about the specified staking pool and the user's staked tokens.
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 rewardTokenPerShare = pool.rewardTokenPerShare; // Initialize the reward per share.
        uint256 lpSupply = pool.lpToken.balanceOf(address(this)); // Get the staked token supply in the pool
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {  // Check if new rewards are available based on block number and staked tokens.

            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number); // Calculate the reward multiplier between the last and current blocks.
            uint256 tokenReward = multiplier.mul(gsPerBlock).mul(pool.allocPoint).div(totalAllocation); // Calculate the total reward tokens for the pool based on allocation points.
            rewardTokenPerShare = rewardTokenPerShare.add(tokenReward.mul(1e12).div(lpSupply));  // Update the reward per share based on new rewards.
        }
        // Calculate the pending rewards for the user and subtract any previously pending rewards.
        return user.amount.mul(rewardTokenPerShare).div(1e12).sub(user.pendingReward);
    } 



   function stake(uint256 _pid, uint256 _amount) public validatePool(_pid) {
         // Get information about the specified staking pool and the user's staked tokens.
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // Update the reward information for the specified staking pool.
        updatePool(_pid);
        if (user.amount > 0) {
            // Check if the user has previously staked tokens in the pool.
            // Calculate the pending rewards for the user based on previous staked amount.
            uint256 pending = user.amount.mul(pool.rewardTokenPerShare).div(1e12).sub(user.pendingReward);
            if(pending > 0) {
                 // If there are pending rewards, transfer them to the user.
                safeGsTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
                 // Check if the user is staking additional tokens.
                 // Transfer tokens from the user to the staking pool contract.
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            // Update the user's staked token amount.
            user.amount = user.amount.add(_amount);
        }
        // Update the user's pending rewards based on the new staked amount.
        user.pendingReward = user.amount.mul(pool.rewardTokenPerShare).div(1e12);
         // Emit a 'Deposit' event to log the user's stake action.
        emit Deposit(msg.sender, _pid, _amount);
    }

  function unstake(uint256 _pid, uint256 _amount) public validatePool(_pid) {
        // Get information about the specified staking pool and the user's staked tokens.
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
         // Ensure that the user's staked amount is greater than or equal to the requested unstake amount.
        require(user.amount >= _amount, "withdraw: not good");
        // Update the reward information for the specified staking pool.
        updatePool(_pid);
        // Calculate the pending rewards for the user based on their current staked amount.
        uint256 pending = user.amount.mul(pool.rewardTokenPerShare).div(1e12).sub(user.pendingReward);
        if(pending > 0) {
            // If there are pending rewards, transfer them to the user.
            safeGsTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
             // Check if the user is unstaking a non-zero amount of tokens.

             // Update the user's staked token amount by subtracting the unstaked amount.
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.pendingReward = user.amount.mul(pool.rewardTokenPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

 function autoCompound() public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.rewardTokenPerShare).div(1e12).sub(user.pendingReward);
            if(pending > 0) {
                user.amount = user.amount.add(pending);
            }
        }
        user.pendingReward = user.amount.mul(pool.rewardTokenPerShare).div(1e12);
    }


    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.pendingReward = 0;
    }

    function safeGsTransfer(address _to, uint256 _amount) internal {
        gspay.safeGsTransfer(_to, _amount);
    }

 function changeDev(address _dev) public {
        require(msg.sender == dev, "Not Authorized");
        dev = _dev;
    }


   

}