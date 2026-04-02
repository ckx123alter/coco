// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Freelance Escrow with milestone payments, platform fee, refund
contract FreelanceEscrow {
    // Auto-increment escrow ID
    uint256 public escrowCounter;
    // Platform fee in bps: 500 = 5%
    uint256 public platformFeeBps = 500;
    // Platform owner address
    address public platformOwner;

    // Constructor: deployer is platform owner
    constructor() {
        platformOwner = msg.sender;
    }

    // Milestone stage structure
    struct Stage {
        string description;
        uint256 amount;
        bool completed;
        bool paid;
    }

    // Escrow status
    enum EscrowStatus {
        Active,
        Cancelled,
        Completed
    }

    // Escrow order structure
    struct Escrow {
        address client;
        address freelancer;
        uint256 totalAmount;
        EscrowStatus status;
        Stage[] stages;
    }

    // ID => Escrow
    mapping(uint256 => Escrow) public escrows;

    // Only platform owner
    modifier onlyPlatform() {
        require(msg.sender == platformOwner, "Not platform");
        _;
    }

    // Only client of this escrow
    modifier onlyClient(uint256 _id) {
        require(msg.sender == escrows[_id].client, "Not client");
        _;
    }

    // Only freelancer of this escrow
    modifier onlyFreelancer(uint256 _id) {
        require(msg.sender == escrows[_id].freelancer, "Not freelancer");
        _;
    }

    // Events
    event EscrowCreated(uint256 escrowId);
    event StageAdded(uint256 escrowId, uint256 stageId);
    event StageEdited(uint256 escrowId, uint256 stageId);
    event StageDeleted(uint256 escrowId, uint256 stageId);
    event StageCompleted(uint256 escrowId, uint256 stageId);
    event PaymentReleased(uint256 escrowId, uint256 stageId);

    // Client creates escrow and deposits ETH
    function createEscrow(address _freelancer) external payable returns (uint256) {
        require(msg.value > 0, "No funds sent");
        escrowCounter++;
        Escrow storage e = escrows[escrowCounter];
        e.client = msg.sender;
        e.freelancer = _freelancer;
        e.totalAmount = msg.value;
        e.status = EscrowStatus.Active;
        emit EscrowCreated(escrowCounter);
        return escrowCounter;
    }

    // Client adds a milestone stage
    function addStage(
        uint256 _id,
        string calldata _desc,
        uint256 _amount
    ) external onlyClient(_id) {
        Escrow storage e = escrows[_id];
        require(e.status == EscrowStatus.Active, "Not active");
        e.stages.push(Stage(_desc, _amount, false, false));
        emit StageAdded(_id, e.stages.length - 1);
    }

    // Client edits unpaid stage
    function editStage(
        uint256 _id,
        uint256 _stageId,
        string calldata _desc,
        uint256 _amount
    ) external onlyClient(_id) {
        Stage storage s = escrows[_id].stages[_stageId];
        require(!s.paid, "Already paid");
        s.description = _desc;
        s.amount = _amount;
        emit StageEdited(_id, _stageId);
    }

    // Client deletes unpaid stage
    function deleteStage(uint256 _id, uint256 _stageId) external onlyClient(_id) {
        Escrow storage e = escrows[_id];
        require(!e.stages[_stageId].paid, "Already paid");
        uint256 last = e.stages.length - 1;
        e.stages[_stageId] = e.stages[last];
        e.stages.pop();
        emit StageDeleted(_id, _stageId);
    }

    // Freelancer marks stage completed
    function markStageCompleted(uint256 _id, uint256 _stageId)
        external
        onlyFreelancer(_id)
    {
        Stage storage s = escrows[_id].stages[_stageId];
        require(!s.completed, "Already completed");
        s.completed = true;
        emit StageCompleted(_id, _stageId);
    }

    // Client releases payment after completion
    function releaseStagePayment(uint256 _id, uint256 _stageId)
        external
        onlyClient(_id)
    {
        Escrow storage e = escrows[_id];
        Stage storage s = e.stages[_stageId];
        require(s.completed, "Stage not completed");
        require(!s.paid, "Already paid");
        s.paid = true;
        uint256 fee = (s.amount * platformFeeBps) / 10000;
        uint256 payout = s.amount - fee;
        (bool sent1, ) = payable(e.freelancer).call{value: payout}("");
        require(sent1, "Freelancer payment failed");
        (bool sent2, ) = payable(platformOwner).call{value: fee}("");
        require(sent2, "Platform fee payment failed");
        emit PaymentReleased(_id, _stageId);
    }

    // Client cancels escrow
    function cancelEscrow(uint256 _id) external onlyClient(_id) {
        Escrow storage e = escrows[_id];
        require(e.status == EscrowStatus.Active, "Not active");
        for (uint256 i = 0; i < e.stages.length; i++) {
            require(!e.stages[i].paid, "Some stages paid");
        }
        e.status = EscrowStatus.Cancelled;
        (bool sent, ) = payable(e.client).call{value: address(this).balance}("");
        require(sent, "Refund failed");
    }

    // Platform updates fee
    function updatePlatformFee(uint256 _bps) external onlyPlatform {
        require(_bps <= 1000, "Max 10%");
        platformFeeBps = _bps;
    }

    // View: get all stages
    function getEscrowStages(uint256 _id) external view returns (Stage[] memory) {
        return escrows[_id].stages;
    }

    // View: stage count
    function getEscrowStageCount(uint256 _id) external view returns (uint256) {
        return escrows[_id].stages.length;
    }

    // View: single stage
    function getEscrowStage(uint256 _id, uint256 _stageId) external view returns (Stage memory) {
        return escrows[_id].stages[_stageId];
    }
}