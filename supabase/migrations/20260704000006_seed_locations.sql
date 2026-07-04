-- Seed Nigerian states, cities, and areas into the locations table.
-- Only inserts if the table is empty to avoid duplicate runs.

DO $$ BEGIN
  IF (SELECT COUNT(*) FROM locations) = 0 THEN

    INSERT INTO locations (state, city, area) VALUES

    -- ── Lagos ─────────────────────────────────────────────────────
    ('Lagos', 'Lagos Island', 'Lagos Island'),
    ('Lagos', 'Lagos Island', 'Victoria Island'),
    ('Lagos', 'Lagos Island', 'Ikoyi'),
    ('Lagos', 'Lagos Island', 'Onikan'),
    ('Lagos', 'Lagos Island', 'Bar Beach'),
    ('Lagos', 'Ikeja', 'Ikeja'),
    ('Lagos', 'Ikeja', 'Allen Avenue'),
    ('Lagos', 'Ikeja', 'Maryland'),
    ('Lagos', 'Ikeja', 'Oregun'),
    ('Lagos', 'Ikeja', 'Toyin Street'),
    ('Lagos', 'Ikeja', 'Agidingbi'),
    ('Lagos', 'Lekki', 'Lekki Phase 1'),
    ('Lagos', 'Lekki', 'Lekki Phase 2'),
    ('Lagos', 'Lekki', 'Ajah'),
    ('Lagos', 'Lekki', 'Chevron'),
    ('Lagos', 'Lekki', 'Jakande'),
    ('Lagos', 'Lekki', 'Sangotedo'),
    ('Lagos', 'Lekki', 'Abraham Adesanya'),
    ('Lagos', 'Yaba', 'Yaba'),
    ('Lagos', 'Yaba', 'Akoka'),
    ('Lagos', 'Yaba', 'Sabo'),
    ('Lagos', 'Yaba', 'Jibowu'),
    ('Lagos', 'Surulere', 'Surulere'),
    ('Lagos', 'Surulere', 'Aguda'),
    ('Lagos', 'Surulere', 'Ojuelegba'),
    ('Lagos', 'Surulere', 'Stadium'),
    ('Lagos', 'Mushin', 'Mushin'),
    ('Lagos', 'Mushin', 'Idi-Oro'),
    ('Lagos', 'Oshodi', 'Oshodi'),
    ('Lagos', 'Oshodi', 'Isolo'),
    ('Lagos', 'Oshodi', 'Mafoluku'),
    ('Lagos', 'Alimosho', 'Egbeda'),
    ('Lagos', 'Alimosho', 'Idimu'),
    ('Lagos', 'Alimosho', 'Ipaja'),
    ('Lagos', 'Alimosho', 'Akowonjo'),
    ('Lagos', 'Alimosho', 'Dopemu'),
    ('Lagos', 'Badagry', 'Badagry'),
    ('Lagos', 'Epe', 'Epe'),
    ('Lagos', 'Ikorodu', 'Ikorodu'),
    ('Lagos', 'Ikorodu', 'Benson'),
    ('Lagos', 'Ikorodu', 'Isawo'),

    -- ── Abuja (FCT) ───────────────────────────────────────────────
    ('FCT', 'Abuja', 'Wuse 1'),
    ('FCT', 'Abuja', 'Wuse 2'),
    ('FCT', 'Abuja', 'Garki'),
    ('FCT', 'Abuja', 'Garki 2'),
    ('FCT', 'Abuja', 'Asokoro'),
    ('FCT', 'Abuja', 'Maitama'),
    ('FCT', 'Abuja', 'Central Business District'),
    ('FCT', 'Abuja', 'Area 1'),
    ('FCT', 'Abuja', 'Area 3'),
    ('FCT', 'Abuja', 'Area 11'),
    ('FCT', 'Abuja', 'Utako'),
    ('FCT', 'Abuja', 'Jabi'),
    ('FCT', 'Abuja', 'Gwarinpa'),
    ('FCT', 'Abuja', 'Life Camp'),
    ('FCT', 'Abuja', 'Kubwa'),
    ('FCT', 'Abuja', 'Lugbe'),
    ('FCT', 'Abuja', 'Lokogoma'),
    ('FCT', 'Abuja', 'Kado'),
    ('FCT', 'Gwagwalada', 'Gwagwalada'),
    ('FCT', 'Kuje', 'Kuje'),

    -- ── Rivers ────────────────────────────────────────────────────
    ('Rivers', 'Port Harcourt', 'GRA Phase 1'),
    ('Rivers', 'Port Harcourt', 'GRA Phase 2'),
    ('Rivers', 'Port Harcourt', 'GRA Phase 3'),
    ('Rivers', 'Port Harcourt', 'Trans-Amadi'),
    ('Rivers', 'Port Harcourt', 'Rumuola'),
    ('Rivers', 'Port Harcourt', 'Rumuigbo'),
    ('Rivers', 'Port Harcourt', 'Rumuokoro'),
    ('Rivers', 'Port Harcourt', 'Diobu'),
    ('Rivers', 'Port Harcourt', 'Mile 1'),
    ('Rivers', 'Port Harcourt', 'Mile 2'),
    ('Rivers', 'Port Harcourt', 'Mile 3'),
    ('Rivers', 'Port Harcourt', 'Old GRA'),
    ('Rivers', 'Port Harcourt', 'New GRA'),
    ('Rivers', 'Port Harcourt', 'Stadium Road'),
    ('Rivers', 'Port Harcourt', 'Eliozu'),
    ('Rivers', 'Port Harcourt', 'Woji'),
    ('Rivers', 'Obio-Akpor', 'Rumuola'),
    ('Rivers', 'Obio-Akpor', 'Rukpokwu'),
    ('Rivers', 'Bonny', 'Bonny Island'),

    -- ── Oyo ──────────────────────────────────────────────────────
    ('Oyo', 'Ibadan', 'Bodija'),
    ('Oyo', 'Ibadan', 'Agodi GRA'),
    ('Oyo', 'Ibadan', 'Jericho'),
    ('Oyo', 'Ibadan', 'Challenge'),
    ('Oyo', 'Ibadan', 'Ring Road'),
    ('Oyo', 'Ibadan', 'Mokola'),
    ('Oyo', 'Ibadan', 'UI'),
    ('Oyo', 'Ibadan', 'Dugbe'),
    ('Oyo', 'Ibadan', 'Iyaganku'),
    ('Oyo', 'Ibadan', 'Sango'),
    ('Oyo', 'Ibadan', 'Iwo Road'),
    ('Oyo', 'Ibadan', 'Ojoo'),
    ('Oyo', 'Ibadan', 'Gate'),
    ('Oyo', 'Ibadan', 'Oluyole'),
    ('Oyo', 'Ogbomosho', 'Ogbomosho'),
    ('Oyo', 'Oyo', 'Oyo'),

    -- ── Kano ─────────────────────────────────────────────────────
    ('Kano', 'Kano', 'Sabon Gari'),
    ('Kano', 'Kano', 'Fagge'),
    ('Kano', 'Kano', 'Nasarawa'),
    ('Kano', 'Kano', 'Bompai'),
    ('Kano', 'Kano', 'GRA'),
    ('Kano', 'Kano', 'Kurna'),
    ('Kano', 'Kano', 'Gwale'),
    ('Kano', 'Kano', 'Tarauni'),
    ('Kano', 'Wudil', 'Wudil'),
    ('Kano', 'Gwarzo', 'Gwarzo'),

    -- ── Anambra ──────────────────────────────────────────────────
    ('Anambra', 'Onitsha', 'Onitsha Main'),
    ('Anambra', 'Onitsha', 'Bridgehead'),
    ('Anambra', 'Onitsha', 'GRA Onitsha'),
    ('Anambra', 'Awka', 'Awka'),
    ('Anambra', 'Awka', 'Unizik Junction'),
    ('Anambra', 'Nnewi', 'Nnewi'),
    ('Anambra', 'Ekwulobia', 'Ekwulobia'),

    -- ── Delta ────────────────────────────────────────────────────
    ('Delta', 'Warri', 'Warri'),
    ('Delta', 'Warri', 'Effurun'),
    ('Delta', 'Warri', 'GRA Warri'),
    ('Delta', 'Warri', 'Okumagba'),
    ('Delta', 'Asaba', 'Asaba'),
    ('Delta', 'Asaba', 'GRA Asaba'),
    ('Delta', 'Ughelli', 'Ughelli'),

    -- ── Enugu ────────────────────────────────────────────────────
    ('Enugu', 'Enugu', 'GRA Enugu'),
    ('Enugu', 'Enugu', 'Independence Layout'),
    ('Enugu', 'Enugu', 'Ogui'),
    ('Enugu', 'Enugu', 'Abakpa'),
    ('Enugu', 'Enugu', 'New Haven'),
    ('Enugu', 'Enugu', 'Trans-Ekulu'),
    ('Enugu', 'Nsukka', 'Nsukka'),

    -- ── Imo ──────────────────────────────────────────────────────
    ('Imo', 'Owerri', 'Owerri'),
    ('Imo', 'Owerri', 'New Owerri'),
    ('Imo', 'Owerri', 'GRA Owerri'),
    ('Imo', 'Orlu', 'Orlu'),
    ('Imo', 'Okigwe', 'Okigwe'),

    -- ── Edo ──────────────────────────────────────────────────────
    ('Edo', 'Benin City', 'GRA Benin'),
    ('Edo', 'Benin City', 'Uselu'),
    ('Edo', 'Benin City', 'Ikpoba Hill'),
    ('Edo', 'Benin City', 'Sapele Road'),
    ('Edo', 'Benin City', 'Oba Market'),
    ('Edo', 'Auchi', 'Auchi'),
    ('Edo', 'Ekpoma', 'Ekpoma'),

    -- ── Kaduna ────────────────────────────────────────────────────
    ('Kaduna', 'Kaduna', 'Barnawa'),
    ('Kaduna', 'Kaduna', 'GRA Kaduna'),
    ('Kaduna', 'Kaduna', 'Sabon Tasha'),
    ('Kaduna', 'Kaduna', 'Kakuri'),
    ('Kaduna', 'Kaduna', 'Tudun Wada'),
    ('Kaduna', 'Zaria', 'Zaria'),
    ('Kaduna', 'Kafanchan', 'Kafanchan'),

    -- ── Kwara ─────────────────────────────────────────────────────
    ('Kwara', 'Ilorin', 'GRA Ilorin'),
    ('Kwara', 'Ilorin', 'Tanke'),
    ('Kwara', 'Ilorin', 'Fate Road'),
    ('Kwara', 'Ilorin', 'Oke-Ose'),
    ('Kwara', 'Offa', 'Offa'),

    -- ── Niger ─────────────────────────────────────────────────────
    ('Niger', 'Minna', 'Minna'),
    ('Niger', 'Minna', 'Bosso'),
    ('Niger', 'Minna', 'Tunga'),
    ('Niger', 'Bida', 'Bida'),
    ('Niger', 'Suleja', 'Suleja'),

    -- ── Plateau ───────────────────────────────────────────────────
    ('Plateau', 'Jos', 'Jos'),
    ('Plateau', 'Jos', 'Rayfield'),
    ('Plateau', 'Jos', 'Bukuru'),
    ('Plateau', 'Jos', 'Terminus'),
    ('Plateau', 'Shendam', 'Shendam'),

    -- ── Cross River ───────────────────────────────────────────────
    ('Cross River', 'Calabar', 'Calabar'),
    ('Cross River', 'Calabar', 'State Housing'),
    ('Cross River', 'Calabar', 'Diamond Hill'),
    ('Cross River', 'Calabar', 'Etta Agbo'),
    ('Cross River', 'Ogoja', 'Ogoja'),

    -- ── Akwa Ibom ─────────────────────────────────────────────────
    ('Akwa Ibom', 'Uyo', 'Uyo'),
    ('Akwa Ibom', 'Uyo', 'Ewet Housing'),
    ('Akwa Ibom', 'Uyo', 'Itam'),
    ('Akwa Ibom', 'Eket', 'Eket'),
    ('Akwa Ibom', 'Ikot Ekpene', 'Ikot Ekpene'),

    -- ── Ondo ─────────────────────────────────────────────────────
    ('Ondo', 'Akure', 'Akure'),
    ('Ondo', 'Akure', 'Alagbaka'),
    ('Ondo', 'Akure', 'FUTA Road'),
    ('Ondo', 'Ondo', 'Ondo'),
    ('Ondo', 'Owo', 'Owo'),

    -- ── Osun ─────────────────────────────────────────────────────
    ('Osun', 'Osogbo', 'Osogbo'),
    ('Osun', 'Osogbo', 'Ataoja'),
    ('Osun', 'Ile-Ife', 'Ile-Ife'),
    ('Osun', 'Ile-Ife', 'OAU'),
    ('Osun', 'Ilesa', 'Ilesa'),

    -- ── Ekiti ────────────────────────────────────────────────────
    ('Ekiti', 'Ado-Ekiti', 'Ado-Ekiti'),
    ('Ekiti', 'Ado-Ekiti', 'Basiri'),
    ('Ekiti', 'Ikere', 'Ikere'),
    ('Ekiti', 'Ikole', 'Ikole'),

    -- ── Ogun ─────────────────────────────────────────────────────
    ('Ogun', 'Abeokuta', 'Abeokuta'),
    ('Ogun', 'Abeokuta', 'Iwe Iroyin'),
    ('Ogun', 'Abeokuta', 'Iberekodo'),
    ('Ogun', 'Sagamu', 'Sagamu'),
    ('Ogun', 'Ijebu-Ode', 'Ijebu-Ode'),
    ('Ogun', 'Ota', 'Ota'),
    ('Ogun', 'Agbara', 'Agbara'),

    -- ── Benue ────────────────────────────────────────────────────
    ('Benue', 'Makurdi', 'Makurdi'),
    ('Benue', 'Makurdi', 'High Level'),
    ('Benue', 'Gboko', 'Gboko'),
    ('Benue', 'Otukpo', 'Otukpo'),

    -- ── Kogi ─────────────────────────────────────────────────────
    ('Kogi', 'Lokoja', 'Lokoja'),
    ('Kogi', 'Lokoja', 'GRA Lokoja'),
    ('Kogi', 'Okene', 'Okene'),
    ('Kogi', 'Anyigba', 'Anyigba'),

    -- ── Nasarawa ─────────────────────────────────────────────────
    ('Nasarawa', 'Lafia', 'Lafia'),
    ('Nasarawa', 'Keffi', 'Keffi'),
    ('Nasarawa', 'Akwanga', 'Akwanga'),

    -- ── Zamfara ──────────────────────────────────────────────────
    ('Zamfara', 'Gusau', 'Gusau'),
    ('Zamfara', 'Kaura Namoda', 'Kaura Namoda'),

    -- ── Kebbi ────────────────────────────────────────────────────
    ('Kebbi', 'Birnin Kebbi', 'Birnin Kebbi'),
    ('Kebbi', 'Argungu', 'Argungu'),

    -- ── Sokoto ───────────────────────────────────────────────────
    ('Sokoto', 'Sokoto', 'Sokoto'),
    ('Sokoto', 'Sokoto', 'GRA Sokoto'),
    ('Sokoto', 'Tambuwal', 'Tambuwal'),

    -- ── Katsina ──────────────────────────────────────────────────
    ('Katsina', 'Katsina', 'Katsina'),
    ('Katsina', 'Daura', 'Daura'),
    ('Katsina', 'Funtua', 'Funtua'),

    -- ── Jigawa ───────────────────────────────────────────────────
    ('Jigawa', 'Dutse', 'Dutse'),
    ('Jigawa', 'Hadejia', 'Hadejia'),

    -- ── Bauchi ───────────────────────────────────────────────────
    ('Bauchi', 'Bauchi', 'Bauchi'),
    ('Bauchi', 'Bauchi', 'GRA Bauchi'),
    ('Bauchi', 'Azare', 'Azare'),

    -- ── Gombe ────────────────────────────────────────────────────
    ('Gombe', 'Gombe', 'Gombe'),
    ('Gombe', 'Gombe', 'Pantami'),
    ('Gombe', 'Kaltungo', 'Kaltungo'),

    -- ── Adamawa ──────────────────────────────────────────────────
    ('Adamawa', 'Yola', 'Yola'),
    ('Adamawa', 'Yola', 'Jimeta'),
    ('Adamawa', 'Mubi', 'Mubi'),

    -- ── Taraba ───────────────────────────────────────────────────
    ('Taraba', 'Jalingo', 'Jalingo'),
    ('Taraba', 'Wukari', 'Wukari'),

    -- ── Borno ────────────────────────────────────────────────────
    ('Borno', 'Maiduguri', 'Maiduguri'),
    ('Borno', 'Maiduguri', 'GRA Maiduguri'),
    ('Borno', 'Biu', 'Biu'),

    -- ── Yobe ─────────────────────────────────────────────────────
    ('Yobe', 'Damaturu', 'Damaturu'),
    ('Yobe', 'Potiskum', 'Potiskum'),

    -- ── Abia ─────────────────────────────────────────────────────
    ('Abia', 'Umuahia', 'Umuahia'),
    ('Abia', 'Aba', 'Aba'),
    ('Abia', 'Aba', 'Ogbor Hill'),
    ('Abia', 'Aba', 'Aba North'),

    -- ── Ebonyi ───────────────────────────────────────────────────
    ('Ebonyi', 'Abakaliki', 'Abakaliki'),
    ('Ebonyi', 'Afikpo', 'Afikpo'),

    -- ── Bayelsa ──────────────────────────────────────────────────
    ('Bayelsa', 'Yenagoa', 'Yenagoa'),
    ('Bayelsa', 'Yenagoa', 'Swali'),
    ('Bayelsa', 'Ogbia', 'Ogbia');

  END IF;
END $$;
