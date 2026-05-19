tableextension 68801 BMGTransSalesExt extends "LSC Trans. Sales Entry"
{
    fields
    {
        // Add changes to table fields here
        field(68800; "Original Lot No."; Code[50])
        {
            DataClassification = CustomerContent;
        }
    }

    keys
    {
        // Add changes to keys here
    }

    fieldgroups
    {
        // Add changes to field groups here
    }

    var
        myInt: Integer;
}