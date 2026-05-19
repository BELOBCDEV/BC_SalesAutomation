pageextension 68801 BMGStoreListExt extends "LSC Store List"
{
    layout
    {
        // Add changes to page layout here
        addafter("Global Dimension 1 Code")
        {
            field("Include in Sales Automation"; Rec."Include in Sales Automation")
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