pageextension 68806 BMGBlockedCustomersInStmtExt extends "LSC Blocked Customers in Stmt."
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
            action(CorrectCustError)
            {
                Caption = 'Correct Cust. Blocked Error';
                ApplicationArea = All;

                trigger OnAction()
                var
                    recTransHeader: Record "LSC Transaction Header";
                    recLSCTransStatus: Record "LSC Transaction Status";
                    recCustomer: Record Customer;
                begin
                    recTransHeader.Reset();
                    recTransHeader.SetRange(Date, WorkDate());
                    recTransHeader.SetRange("Store No.", Rec."Store No.");

                    if recTransHeader.FindFirst() then
                        repeat
                            recCustomer.Reset();
                            recCustomer.SetRange("No.", recTransHeader."Customer No.");

                            if recCustomer.FindFirst() then begin
                                if not recCustomer.IsBlocked() then begin
                                    recLSCTransStatus.Reset();
                                    recLSCTransStatus.SetRange("Store No.", recTransHeader."Store No.");
                                    recLSCTransStatus.SetRange("POS Terminal No.", recTransHeader."POS Terminal No.");
                                    recLSCTransStatus.SetRange("Transaction No.", recTransHeader."Transaction No.");

                                    if recLSCTransStatus.FindFirst() then begin
                                        recLSCTransStatus."Blocked Customer" := false;
                                        recLSCTransStatus.Modify();
                                    end;
                                end;
                            end;
                        until recTransHeader.Next() = 0;

                end;
            }
        }
    }

    var
        myInt: Integer;
}