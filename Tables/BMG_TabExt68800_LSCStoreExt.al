tableextension 68800 BMGStoreExt extends "LSC Store"
{
    fields
    {
        // Add changes to table fields here
        field(68800; "Include in Sales Automation"; Boolean)
        {
            DataClassification = CustomerContent;
        }
        field(68801; "Reclass Doc. Prefix"; Code[10])
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