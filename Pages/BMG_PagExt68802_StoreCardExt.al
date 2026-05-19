pageextension 68802 BMGStoreCard extends "LSC Store Card"
{
    layout
    {
        // Add changes to page layout here
        addafter("Show Availab. on POS Button")
        {
            field("Include in Sales Automation"; Rec."Include in Sales Automation")
            {
                ApplicationArea = All;
            }
            field("Reclass Prefix"; Rec."Reclass Doc. Prefix")
            {
                ApplicationArea = All;
            }
        }
    }

    actions
    {
        // Add changes to page actions here
    }

    var
        myInt: Integer;
}