module tb_4loops;

    // Testbench Parameters
    localparam N = 5; // Number of iterations of each loop
    localparam CLK_PERIOD = 10;

    // Testbench Signals
    reg clk, reset, stall, flush;
    reg branch_taken_execute;
    reg [31:0] pc_execute, target_pc_execute;
    wire [31:0] pc_out;
    wire btb_hit;
    wire [31:0] predicted_pc;

    // Instantiate the DUT
    fetch_unit_with_btb dut (
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .flush(flush),
        .branch_taken_execute(branch_taken_execute),
        .pc_execute(pc_execute),
        .target_pc_execute(target_pc_execute),
        .pc_out(pc_out),
        .btb_hit(btb_hit),
        .predicted_pc(predicted_pc)
    );

    // Simulation Variables
    reg [31:0] loop_start_pc [0:3];  // Start of each loop
    reg [31:0] loop_end_pc [0:3];    // End of each loop
    reg [31:0] loop_target_pc [0:3]; // Target of each loop branch
    reg [31:0] current_pc;
    reg [1:0] current_loop;          // Index of current loop

    integer correct_predictions = 0, total_predictions = 0;    // total predictions indicate predictions due to btb hit
    integer total_instructions = 0, total_branch_instructions = 0;
    integer current_loop_branch_instructions = 0;

    // Clock Generation
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Test Sequence
    initial begin

        // Enable VCD Dump
        $dumpfile("tb_4loops.vcd");
        $dumpvars(0, tb_4loops);

        // Initialize Signals
        clk = 0; reset = 1; stall = 0; flush = 0;
        branch_taken_execute = 0; pc_execute = 0; target_pc_execute = 0;

        // Initialize Loop Parameters
        loop_start_pc[0] = 32'h00000004; loop_end_pc[0] = 32'h00000014; loop_target_pc[0] = 32'h00000004;
        loop_start_pc[1] = 32'h00000024; loop_end_pc[1] = 32'h00000034; loop_target_pc[1] = 32'h00000024;
        loop_start_pc[2] = 32'h00000044; loop_end_pc[2] = 32'h00000054; loop_target_pc[2] = 32'h00000044;
        loop_start_pc[3] = 32'h00000064; loop_end_pc[3] = 32'h00000074; loop_target_pc[3] = 32'h00000064;

        // Deassert Reset
        #(CLK_PERIOD) reset = 0;

        // Simulate Execution of 4 Loops
        current_pc = 32'b0;
        for (integer current_loop = 0; current_loop < 8; current_loop = current_loop + 1) begin
            current_loop_branch_instructions = 0;

            while (current_loop_branch_instructions < N) begin
                // Fetch Stage
                if (!stall) begin
                    total_instructions = total_instructions + 1;

                    // Simulate Branch Instruction
                    if ((current_pc == loop_end_pc[current_loop % 4]) || (branch_taken_execute == 1 && current_loop_branch_instructions == 0)) begin
                        total_branch_instructions = total_branch_instructions + 1;
                        current_loop_branch_instructions = current_loop_branch_instructions + 1;

                        // Condition for loop branch: loop back until exit condition
                        branch_taken_execute = (current_loop_branch_instructions < N);
                        pc_execute = current_pc;
                        target_pc_execute = branch_taken_execute ? loop_target_pc[current_loop % 4] : loop_end_pc[current_loop % 4] + 4;

                        // Check BTB prediction
                        if (btb_hit) begin
                            if ((branch_taken_execute && predicted_pc == target_pc_execute) ||
                                (!branch_taken_execute && predicted_pc == pc_execute + 4)) begin
                                correct_predictions = correct_predictions + 1;
                            end
                        end

                        flush = 1;
                        #(CLK_PERIOD);
                        flush = 0;

                        current_pc = branch_taken_execute ? target_pc_execute : loop_end_pc[current_loop % 4] + 4;
                    end else begin
                        branch_taken_execute = 0;
                        current_pc = current_pc + 4; // Sequential execution
                    end
                end

                // Update BTB (happens internally in the DUT)
                #(CLK_PERIOD);
                if (btb_hit) begin
                    // If there was  a btb hit that means we are predicting pc referring to btb table
                    total_predictions = total_predictions + 1;
                end

                // Continuous Monitoring after each instruction execution
                $display("Loop: %0d | Total Instructions: %0d | Current PC: %0h | Branch Taken: %b | BTB Hit: %b | Predicted PC: %0h | Correct Predictions: %0d | Total Predictions: %0d",
                         current_loop % 4, total_instructions, current_pc, branch_taken_execute, btb_hit, predicted_pc, correct_predictions, total_predictions);
            end
            
            branch_taken_execute = 1;
            pc_execute = (current_loop < 8) ? loop_start_pc[(current_loop + 1) % 4] - 4 : 0;
            target_pc_execute = (current_loop < 8) ? ( loop_start_pc[(current_loop + 1) % 4] ): 0;
            current_pc = pc_execute;
            
            // Update BTB (happens internally in the DUT)
            #(CLK_PERIOD);
            
        end

        // Display Results
        $display("Simulation Results:");
        $display("-------------------");
        $display("Total Instructions        : %0d", total_instructions);
        $display("Total Branch Instructions : %0d", total_branch_instructions);
        $display("Total Predictions         : %0d", total_predictions);
        $display("Correct Predictions       : %0d", correct_predictions);
        $display("Prediction Accuracy       : %0.2f%%",
                 (total_predictions > 0) ? (correct_predictions * 100.0 / total_branch_instructions) : 0.0);
        $display("BTB Hit Rate              : %0.2f%%",
                 (total_predictions > 0) ? (total_predictions * 100.0 / total_branch_instructions) : 0.0);

        // End Simulation
        $stop;
    end

endmodule
