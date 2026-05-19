pageextension 68804 BMGLSCBlockedItemsinStmtExt extends "LSC Blocked Items in Stmt."
{
    layout
    {
        // Add changes to page layout here
    }

    actions
    {
        // Add changes to page actions here
        addafter("&Print")
        {
            action(CheckItemNoStatus)
            {
                Caption = 'Correct Item Blocked Error';
                ApplicationArea = All;
                trigger OnAction()
                var
                    recLSCTransSales: Record "LSC Trans. Sales Entry";
                    recLSCTransStatus: Record "LSC Transaction Status";
                    recItem: Record Item;
                begin
                    recLSCTransSales.Reset();
                    recLSCTransSales.SetRange("Trans. Date", WorkDate());
                    recLSCTransSales.SetRange("Store No.", Rec."Store No.");
                    recLSCTransSales.SetRange("Transaction Code", recLSCTransSales."Transaction Code"::"Item Blocked");

                    if recLSCTransSales.FindFirst() then
                        repeat
                            //Message('Item No. is %1', recLSCTransSales."Item No.");
                            recItem.Reset();
                            recItem.SetRange("No.", recLSCTransSales."Item No.");

                            if recItem.FindFirst() then begin
                                if recItem.Blocked then
                                    Message('Item no. %1 is blocked.', recLSCTransSales."Item No.");
                                if not recItem.Blocked then begin
                                    //Message('Item no. %1 is not blocked.', recLSCTransSales."Item No.");
                                    recLSCTransSales."Transaction Code" := recLSCTransSales."Transaction Code"::"Item on File";
                                    recLSCTransSales.Modify();

                                    recLSCTransStatus.Reset();
                                    recLSCTransStatus.SetRange("Store No.", recLSCTransSales."Store No.");
                                    recLSCTransStatus.SetRange("POS Terminal No.", recLSCTransSales."POS Terminal No.");
                                    recLSCTransStatus.SetRange("Transaction No.", recLSCTransSales."Transaction No.");

                                    if recLSCTransStatus.FindFirst() then begin
                                        recLSCTransStatus."Items Blocked" := recLSCTransStatus."Items Blocked" - 1;
                                        recLSCTransStatus.Modify();
                                    end;
                                end;
                            end;
                        until recLSCTransSales.Next() = 0;
                end;
            }
        }
    }

    var
        myInt: Integer;
}