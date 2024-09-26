function Get-RandomPassword {
    param (
        [int]$PasswordLength = 3
    )

    $SourceWords = 'Adams', 'Alpha', 'Boston', 'Bravo', 'Charlie', 'Chicago', 'Delta', 'Denver', 'Easy',
                   'Echo', 'Foxtrot', 'Frank', 'George', 'Golf', 'Henry', 'Hotel', 'Ida', 'India', 'John', 
                   'Juliet', 'Kilo', 'King', 'Lima', 'Lincoln', 'Mary', 'Mike', 'November', 'Ocean', 'Oscar', 
                   'Papa', 'Peter', 'Quebec', 'Queen', 'Roger', 'Romeo', 'Sierra', 'Sugar', 'Tango', 'Thomas', 
                   'Uniform', 'Union', 'Victor', 'Whiskey', 'William', 'Yankee', 'Young', 'Zulu'
    $SourceNumbers = 0..100

    $PasswordWords = @()

    while ($PasswordWords.Count -lt $PasswordLength) {
        $RandomWord = Get-Random -InputObject $SourceWords
        if ($RandomWord -notin $PasswordWords) {
            $PasswordWords += $RandomWord
        }
    }

    $RandomNumber = Get-Random -InputObject $SourceNumbers

    $Password = ($PasswordWords -join '-') + "$RandomNumber"
    return $Password
}
