$localprograms = choco list --localonly
if ($localprograms -like "*forticlient*")
{
    choco upgrade forticlient
}
Else
{
    choco install forticlient -y
}
