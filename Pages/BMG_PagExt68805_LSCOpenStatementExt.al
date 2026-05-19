pageextension 68805 BMGLSCOpenStatementExt extends "LSC Open Statement"
{
    layout
    {
        // Add changes to page layout here
    }

    actions
    {
        // Add changes to page actions here
        addafter("Serial/Lot &No. Not Valid")
        {
            action(RevertToLotNosNotValid)
            {
                Caption = 'Revert to Lot Nos Not Valid';
                ApplicationArea = All;

                trigger OnAction()
                var
                    recLSCTransStatus: Record "LSC Transaction Status";
                    recItemLedgEntry: Record "Item Ledger Entry" temporary;
                    recLSCTransSales: Record "LSC Trans. Sales Entry";
                    bolOK: Boolean;
                begin

                    bolOK := Confirm('Are you sure you want to restore the errors encountered recently?', false);

                    if bolOK then begin
                        recLSCTransSales.Reset();
                        recLSCTransSales.SetRange("Trans. Date", WorkDate());
                        recLSCTransSales.SetRange("Store No.", Rec."Store No.");
                        recLSCTransSales.SetFilter("Original Lot No.", '<>%1', '');

                        if not recLSCTransSales.FindFirst() then
                            error('No error/s encountered recently.');
                        //Message('Store No. %1 is selected', Rec."Store No.");
                        if recLSCTransSales.FindFirst() then begin
                            //Message('Record found for Store No. %1', Rec."Store No.");
                            repeat
                                recLSCTransSales."Serial/Lot No. Not Valid" := true;
                                recLSCTransSales."Lot No." := recLSCTransSales."Original Lot No.";
                                recLSCTransSales."Original Lot No." := '';
                                recLSCTransSales.Modify();

                                recLSCTransStatus.Reset();
                                recLSCTransStatus.SetRange("Store No.", recLSCTransSales."Store No.");
                                recLSCTransStatus.SetRange("POS Terminal No.", recLSCTransSales."POS Terminal No.");
                                recLSCTransStatus.SetRange("Transaction No.", recLSCTransSales."Transaction No.");

                                if recLSCTransStatus.FindFirst() then begin
                                    recLSCTransStatus."Serial/Lot No. Not Valid" := recLSCTransStatus."Serial/Lot No. Not Valid" + 1;
                                    recLSCTransStatus.Modify();
                                end;
                            until recLSCTransSales.Next() = 0;
                        end;
                    end;
                end;

            }
        }
    }

    var
        myInt: Integer;
}