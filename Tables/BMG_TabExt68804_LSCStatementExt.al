tableextension 68804 BMGLSCStatementExt extends "LSC Statement"
{
    fields
    {
        // Add changes to table fields here
        field(68000; "BMG Difference Amount"; Decimal)
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