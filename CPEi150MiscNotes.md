it will allow you to load any root cert, as long as it is in DER format (not PEM)

## Password Bypass ##
This bookmarklet will log you in automatically if run when on the device login page:

`javascript:document.getElementById('uiPostUserName').value='Admin';document.getElementById('uiPostPassword').value='Tools';document.getElementById('uiPostForm').submit();`