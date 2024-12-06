module fetch_unit_with_btb (
    input clk,
    input reset,
    input stall,
    input flush,
    input branch_taken_execute,        // Actual branch behavior from Execute stage
    input [31:0] pc_execute,           // Branch instruction address from Execute stage
    input [31:0] target_pc_execute,    // Target address from Execute stage
    output reg [31:0] pc_out,          // Next PC for Fetch stage
    output reg btb_hit,                // BTB hit signal
    output reg [31:0] predicted_pc     // Predicted PC signal
);

    // BTB Parameters
    localparam NUM_SETS = 16;          // Number of sets (index bits are [5:2])
    localparam NUM_WAYS = 4;           // Number of ways per set

    // Predictor states
    localparam STRONGLY_NOT_TAKEN = 2'b00;
    localparam WEAKLY_NOT_TAKEN   = 2'b01;
    localparam WEAKLY_TAKEN       = 2'b10;
    localparam STRONGLY_TAKEN     = 2'b11;

    // BTB: 4-Way Associative
    reg [27:0] btb_tag [NUM_SETS-1:0][NUM_WAYS-1:0];         // Tag bits (upper PC bits)
    reg [31:0] btb_target_pc [NUM_SETS-1:0][NUM_WAYS-1:0];   // Target PC
    reg [1:0] btb_predictor [NUM_SETS-1:0][NUM_WAYS-1:0];    // 2-bit saturating counter
    reg btb_valid [NUM_SETS-1:0][NUM_WAYS-1:0];              // Valid bit
    reg [1:0] fifo_pointer [NUM_SETS-1:0];                   // FIFO queue pointer for replacement

    // Current PC
    reg [31:0] current_pc;

    // Internal Signals
    wire [3:0] set_index;              // Index derived from PC(current)
    wire [27:0] tag_bits;              // Tag derived from PC(current)

    // To Extract Set Index and Tag of PC in execute stage
    wire [3:0] set_index_execute;
    wire [27:0] tag_bits_execute;
    assign set_index_execute = pc_execute[5:2]; // Using PC from Execute stage
    assign tag_bits_execute = pc_execute[31:6]; // Tag of PC from Execute stage

    // Extracting Set Index (bits 5 to 2 of PC, skipping the last 2 bits as address size is 32 bits and thus last two bits will always be 00)
    assign set_index = current_pc[5:2];
    // Extracting Tag (remaining upper bits of PC current)
    assign tag_bits = current_pc[31:6];

    // Compute Next PC
    always @(*) begin
        btb_hit = 0;
        predicted_pc = current_pc + 4; // Default next PC is sequential

        // Searching BTB set for a match
        for (integer i = 0; i < NUM_WAYS; i = i + 1) begin
            if (btb_valid[set_index][i] && btb_tag[set_index][i] == tag_bits) begin
                btb_hit = 1;
                if (btb_predictor[set_index][i][1]) // Predictor suggests branch taken
                    predicted_pc = btb_target_pc[set_index][i];
            end
        end
    end

    // Update PC
    always @(posedge clk or posedge reset) begin
        if (reset)
            current_pc <= 32'b0;
        else if (!stall)
            current_pc <= flush ? pc_execute : predicted_pc;
    end

    // Output the current PC
    always @(*) begin
        pc_out = current_pc;
    end

    // Updating BTB on Branch Resolution
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            // Invalidate all BTB entries and reset FIFO pointers
            for (integer set = 0; set < NUM_SETS; set = set + 1) begin
                for (integer way = 0; way < NUM_WAYS; way = way + 1) begin
                    btb_valid[set][way] <= 0;
                end
                fifo_pointer[set] <= 0;
            end
        end else if (branch_taken_execute || flush) begin  // If branch was taken actually or there was a pipeline flush due to misprediction
            // Check for an existing entry in the BTB set
            integer i, replace_way;
            reg found;
            found = 0;
            for (i = 0; i < NUM_WAYS; i = i + 1) begin
                if (btb_valid[set_index_execute][i] && btb_tag[set_index_execute][i] == tag_bits_execute) begin

                    // Update existing BTB entry only if moving between weakly taken and weakly not taken
                    if ((btb_predictor[set_index_execute][i] == WEAKLY_TAKEN && !branch_taken_execute) ||
                        (btb_predictor[set_index_execute][i] == WEAKLY_NOT_TAKEN && branch_taken_execute)) begin
                        btb_target_pc[set_index_execute][i] <= target_pc_execute;
                    end

                    // Adjust predictor
                    if (branch_taken_execute) begin
                        btb_predictor[set_index_execute][i] <= (btb_predictor[set_index_execute][i] == STRONGLY_TAKEN) ? STRONGLY_TAKEN :
                                                       (btb_predictor[set_index_execute][i] + 1);
                    end else begin
                        btb_predictor[set_index_execute][i] <= (btb_predictor[set_index_execute][i] == STRONGLY_NOT_TAKEN) ? STRONGLY_NOT_TAKEN :
                                                       (btb_predictor[set_index_execute][i] - 1);
                    end
                    found = 1;
                end
            end
            if (!found) begin
                // Replace the FIFO entry
                replace_way = fifo_pointer[set_index_execute];
                btb_tag[set_index_execute][replace_way] <= tag_bits_execute;
                btb_target_pc[set_index_execute][replace_way] <= target_pc_execute;
                btb_predictor[set_index_execute][replace_way] <= branch_taken_execute ? WEAKLY_TAKEN : WEAKLY_NOT_TAKEN;
                // Validating the entry
                btb_valid[set_index_execute][replace_way] <= 1;
                // Update FIFO pointer
                fifo_pointer[set_index_execute] <= (fifo_pointer[set_index_execute] + 1) % NUM_WAYS;
            end
        end
    end
endmodule
