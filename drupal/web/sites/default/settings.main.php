<?php

# Fix samesite cookie
ini_set('session.cookie_secure', 1);
ini_set('session.cookie_samesite', 'Strict');
