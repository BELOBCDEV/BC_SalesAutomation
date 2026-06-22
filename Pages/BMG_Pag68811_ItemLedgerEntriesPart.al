page 68811 BMGItemLedgerEntriesPart
{
    PageType = ListPart;
    ApplicationArea = All;
    SourceTable = "Item Ledger Entry";
    Caption = 'Item History';
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Lines)
            {
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                }
                field("Posting Date"; Rec."Posting Date")
                {
                    ApplicationArea = All;
                }
                field("Entry Type"; Rec."Entry Type")
                {
                    ApplicationArea = All;
                }
                field("Document No."; Rec."Document No.")
                {
                    ApplicationArea = All;
                }
                field("Item No."; Rec."Item No.")
                {
                    ApplicationArea = All;
                }
                field(Description; Rec.Description)
                {
                    ApplicationArea = All;
                }
                field("Location Code"; Rec."Location Code")
                {
                    ApplicationArea = All;
                }
                field("Lot No."; Rec."Lot No.")
                {
                    ApplicationArea = All;
                }
                field("Serial No."; Rec."Serial No.")
                {
                    ApplicationArea = All;
                }
                field(Quantity; Rec.Quantity)
                {
                    ApplicationArea = All;
                }
                field("Remaining Quantity"; Rec."Remaining Quantity")
                {
                    ApplicationArea = All;
                }
                field(Open; Rec.Open)
                {
                    ApplicationArea = All;
                }

            }
        }
    }

    procedure SetItemFilter(pItemNo: Code[20]; pLocationCode: Code[20])
    begin
        Rec.Reset();
        if pItemNo <> '' then
            Rec.SetRange("Item No.", pItemNo);
        if pLocationCode <> '' then
            Rec.SetRange("Location Code", pLocationCode);
        Rec.SetFilter("Remaining Quantity", '<>%1', 0);
        CurrPage.Update(false);
    end;
}
